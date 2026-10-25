import SwiftUI
@preconcurrency import GRDB
#if canImport(UIKit)
import UIKit
#endif

enum TaobaoImportStep: String, Codable { case select = "选择商品", prepare = "补全资料", detail = "确认商品", result = "导入完成" }

@MainActor
final class TaobaoImportViewModel: ObservableObject {
    @Published private(set) var orders: [TaobaoOrder] = []
    @Published var selectedKeys = Set<String>()
    @Published private(set) var brands: [Brand] = []
    @Published private(set) var categories: [Category] = []
    @Published var missingAttributes: [TaobaoMissingAttribute] = []
    @Published var drafts: [TaobaoImportDraft] = []
    @Published private(set) var step: TaobaoImportStep = .select
    @Published private(set) var isWorking = false
    @Published private(set) var fileCount = 0
    @Published private(set) var duplicateOrders = 0
    @Published private(set) var alreadyImported = Set<String>()
    @Published private(set) var result: TaobaoImportResult?
    @Published var error: String?
    private let repository: TaobaoImportRepository
    private let db: DatabaseQueue
    private var temporaryImages = Set<String>()
    private var committed = false
    @Published private(set) var sessions: [OrderImportSession] = []
    @Published private(set) var files: [OrderImportFile] = []
    @Published private(set) var conflicts: [ImportSourceConflict] = []
    @Published private(set) var session: OrderImportSession?
    @Published private(set) var draftError: String?
    private var choices: [String: String] = [:]
    private var saveTail: Task<Void, Error>?
    private var ready = false
    private var loaded = false
    private var sessionRepository: OrderImportSessionRepository { OrderImportSessionRepository(db: db) }
    var persistenceKey: String { (try? OrderImportSource.json(snapshot) + OrderImportSource.json(drafts) + OrderImportSource.json(files)) ?? "" }
    private var snapshot: OrderImportSnapshot { OrderImportSnapshot(orders: orders, selectedKeys: selectedKeys, choices: choices, step: step, missingAttributes: missingAttributes, result: result) }
    func saveDraft() async -> Bool {
        guard ready, session != nil else { return true }
        let previous = saveTail
        let task = Task { @MainActor in
            if let previous { _ = try? await previous.value }
            guard let current = self.session else { return }
            let snapshot = self.snapshot, rows = self.drafts, files = self.files
            self.session = try await self.sessionRepository.save(current, snapshot: snapshot, drafts: rows, files: files)
            try? ImageFileHelper.deleteUnreferenced(paths: Array(self.temporaryImages), db: self.db)
            self.temporaryImages = []
        }
        saveTail = task
        do { try await task.value; draftError = nil; return true }
        catch { draftError = userFacingError(error); return false }
    }
    func refreshSessions() async {
        do { sessions = try await sessionRepository.sessions() } catch { self.error = userFacingError(error) }
    }
    func restore(_ id: String) async {
        guard !isWorking else { return }; isWorking = true; ready = false
        if let saveTail { _ = try? await saveTail.value }
        defer { isWorking = false }
        do {
            let value = try await sessionRepository.load(id)
            session = value.session; orders = value.snapshot.orders; selectedKeys = value.snapshot.selectedKeys
            choices = value.snapshot.choices; step = value.snapshot.step; result = value.snapshot.result
            missingAttributes = value.snapshot.missingAttributes; drafts = value.drafts; files = value.files
            fileCount = files.count; committed = step == .result; draftError = nil
            conflicts = OrderImportSessionRepository.merge(files, choices: choices).conflicts
            ready = true
        } catch { self.error = userFacingError(error) }
    }
    func newSession() async {
        if !(await saveDraft()) { return }
        ready = false; session = OrderImportSession(dataJson: "{}")
        orders = []; selectedKeys = []; drafts = []; files = []; conflicts = []; choices = [:]
        result = nil; step = .select; committed = false; fileCount = 0; duplicateOrders = 0; missingAttributes = []; temporaryImages = []
        ready = true; _ = await saveDraft(); await refreshSessions()
    }
    @discardableResult func discardSession(_ id: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true; defer { isWorking = false }
        if let saveTail { _ = try? await saveTail.value }
        let current = session?.id == id, wasReady = ready
        if current { ready = false }
        do {
            let temporary = current ? Array(temporaryImages) : []
            try await sessionRepository.discard(id)
            if current { session = nil; orders = []; drafts = []; files = []; conflicts = []; selectedKeys = []; temporaryImages = []; step = .select }
            try? ImageFileHelper.deleteUnreferenced(paths: temporary, db: db)
            await refreshSessions(); return true
        } catch { ready = wasReady; self.error = userFacingError(error); return false }
    }
    func chooseSource(orderId: String, hash: String) {
        choices[orderId] = hash; mergeFiles()
    }
    func removeFile(_ id: String) { files.removeAll { $0.id == id }; mergeFiles() }
    private func mergeFiles() {
        let merged = OrderImportSessionRepository.merge(files, choices: choices)
        orders = merged.orders; conflicts = merged.conflicts; duplicateOrders = merged.duplicates; fileCount = files.count
        let available = Set(orders.flatMap(\.items).map(\.id))
        selectedKeys.formIntersection(available)
        let units = Set(orders.flatMap { (try? OrderImportSource.units($0)) ?? [] }.map(\.id))
        let hashes = Dictionary(uniqueKeysWithValues: orders.map { ($0.orderId, OrderImportSource.snapshot($0)) })
        drafts.removeAll { !units.contains($0.id) || hashes[$0.original.orderId] != $0.sourceSnapshotHash }
        step = .select; committed = false; result = nil
    }
    func resumeRemaining() { step = .detail; result = nil; committed = false; session?.pendingOperationId = nil; for i in drafts.indices { drafts[i].included = false } }


    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        repository = TaobaoImportRepository(db: db)
    }

    var hasUnsavedInput: Bool { session != nil && !committed }
    var includedCount: Int { drafts.filter(\.included).count }
    var importItemCount: Int {
        let included = drafts.filter(\.included)
        let keys = Set(included.map(\.id))
        return included.count - included.filter { $0.role == .balance && $0.pairedWith.map(keys.contains) == true }.count
    }

    func loadAttributes() async {
        do {
            apply(try await repository.attributes())
            if !loaded { loaded = true; await refreshSessions(); ready = true }
        }
        catch { if !Task.isCancelled { self.error = userFacingError(error) } }
    }

    func loadFiles(_ urls: [URL]) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if session == nil { session = OrderImportSession(dataJson: "{}"); ready = true }
            let sessionID = session!.id
            let worker = Task.detached(priority: .userInitiated) {
                guard !urls.isEmpty, urls.count <= 50 else { throw ValidationError.invalid("请选择 1 至 50 个文件") }
                var results: [OrderImportFile] = []; var total = 0
                for url in urls {
                    try Task.checkCancellation()
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    var file = OrderImportFile(sessionId: sessionID, name: url.lastPathComponent, sha256: "unread:" + UUID().uuidString)
                    do {
                        guard url.pathExtension.lowercased() == "xlsx" else { throw ValidationError.invalid("仅支持 .xlsx 文件") }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        total += size
                        guard size <= TaobaoOrderParser.maximumFileSize, total <= 64 * 1024 * 1024 else { throw ValidationError.invalid("订单文件过大，请分批选择") }
                        let data = try Data(contentsOf: url)
                        file.sha256 = OrderImportSource.fileHash(data)
                        file.dataJson = try OrderImportSource.json(TaobaoOrderParser.parse(data))
                    } catch { file.problem = userFacingError(error) }
                    results.append(file)
                }
                return results
            }
            let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            apply(try await repository.attributes())
            var hashes = Set(files.map(\.sha256))
            files += parsed.filter { hashes.insert($0.sha256).inserted }
            mergeFiles()
            selectedKeys.formUnion(orders.filter { $0.orderStatus == "交易成功" }.flatMap(\.items).filter { !$0.styleSpec.contains("意向金") && !alreadyImported.contains($0.id) }.map(\.id))
            _ = await saveDraft(); await refreshSessions()
        } catch { if !Task.isCancelled { self.error = "读取订单失败：" + userFacingError(error) } }
    }

    func selectAll(_ selected: Bool) {
        guard !isWorking else { return }
        selectedKeys = selected ? Set(orders.flatMap(\.items).filter { !alreadyImported.contains($0.id) }.map(\.id)) : []
    }

    func prepare() {
        guard !isWorking, conflicts.isEmpty, !selectedKeys.isEmpty else { return }
        let items = orders.flatMap(\.items).filter { selectedKeys.contains($0.id) }
        var missing: [TaobaoMissingAttribute] = []
        for item in items {
            if !item.shopName.isEmpty, TaobaoImportMatching.brand(item.shopName, in: brands) == nil {
                missing.append(TaobaoMissingAttribute(name: item.shopName, kind: .brand, group: .clothing))
            }
            if let type = item.parsedType, TaobaoImportMatching.category(type, in: categories) == nil {
                missing.append(TaobaoMissingAttribute(name: type, kind: .category, group: TaobaoImportMatching.group(type)))
            }
        }
        var seen = Set<String>()
        missingAttributes = missing.filter { seen.insert($0.id.lowercased()).inserted }.sorted { $0.id < $1.id }
        if missingAttributes.isEmpty { buildDrafts() }
        else { step = .prepare }
    }

    func confirmPrepare() async {
        guard !isWorking else { return }
        isWorking = true
        let snapshot = missingAttributes
        defer { isWorking = false }
        do {
            let attributes = try await repository.prepareAttributes(snapshot)
            apply(attributes)
            buildDrafts()
        } catch { self.error = "补全资料失败：" + userFacingError(error) }
    }

    func backToSelection() { guard !isWorking else { return }; step = .select }

    func addAttribute(name: String, kind: TaobaoMissingKind, group: CategoryGroup, to id: String) async throws {
        guard !isWorking else { throw ValidationError.invalid("正在处理，请稍候") }
        isWorking = true
        defer { isWorking = false }
        let name = try InputValidation.name(name)
        let attributes = try await repository.prepareAttributes([TaobaoMissingAttribute(name: name, kind: kind, group: group)])
        apply(attributes)
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        if kind == .brand { drafts[index].brandId = attributes.brands.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id ?? 0 }
        else { drafts[index].categoryId = attributes.categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id ?? 0 }
    }

    private func buildDrafts() {
        let existing = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
        let built = orders.flatMap { order -> [TaobaoImportDraft] in
            let rows = (try? OrderImportSource.drafts(order)) ?? []
            return rows.filter { selectedKeys.contains("\($0.original.orderId):\($0.original.lineIndex)") }.map { value in
                var draft = existing[value.id] ?? value
                if draft.brandId == 0 { draft.brandId = TaobaoImportMatching.brand(draft.original.shopName, in: brands)?.id ?? 0 }
                if draft.categoryId == 0 { draft.categoryId = TaobaoImportMatching.category(draft.original.parsedType, in: categories)?.id ?? 0 }
                return draft
            }
        }
        let keys = Set(built.map(\.id))
        drafts = TaobaoImportMatching.autoPair(built.map { draft in
            var draft = draft
            if let pair = draft.pairedWith, !keys.contains(pair) { draft.pairedWith = nil }
            return draft
        })
        step = .detail
    }

    func setRole(_ role: TaobaoPaymentRole, for id: String) {
        guard !isWorking, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        if drafts[index].role != role { unpair(id); drafts[index].role = role }
    }

    func pair(_ id: String, with otherID: String) {
        guard !isWorking, let first = drafts.firstIndex(where: { $0.id == id }), let second = drafts.firstIndex(where: { $0.id == otherID }), first != second,
              drafts[first].role != .full, drafts[second].role != .full, drafts[first].role != drafts[second].role else { return }
        unpair(id); unpair(otherID)
        drafts[first].pairedWith = otherID; drafts[second].pairedWith = id
        drafts[first].included = true; drafts[second].included = true
    }

    func unpair(_ id: String) {
        guard !isWorking, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        if let pair = drafts[index].pairedWith, let partner = drafts.firstIndex(where: { $0.id == pair }) { drafts[partner].pairedWith = nil }
        drafts[index].pairedWith = nil
    }

    func setIncluded(_ included: Bool, for id: String) {
        guard !isWorking, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].included = included
        if let pair = drafts[index].pairedWith, let partner = drafts.firstIndex(where: { $0.id == pair }) { drafts[partner].included = included }
    }

    func addImage(_ data: Data, to id: String) {
        guard !isWorking, !Task.isCancelled, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let path = ImageFileHelper.save(image: image) else { error = "无法读取或保存这张图片"; return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { error = "无法保存这张图片"; return }
        #endif

        temporaryImages.insert(path); drafts[index].imagePath = path
    }

    func removeImage(from id: String) {
        guard !isWorking, let index = drafts.firstIndex(where: { $0.id == id }) else { return }

        drafts[index].imagePath = nil
    }

    func executeImport() async {
        guard !isWorking else { return }; isWorking = true
        defer { isWorking = false }
        session?.pendingOperationId = session?.pendingOperationId ?? UUID().uuidString
        guard await saveDraft(), let current = session else { error = draftError ?? "请先保存导入会话"; return }
        let frozen = snapshot, rows = drafts
        do {
            result = try await sessionRepository.commit(session: current, snapshot: frozen, drafts: rows)
            let saved = try await sessionRepository.load(current.id); session = saved.session
            committed = true; step = .result; temporaryImages = []; await refreshSessions()
        } catch { self.error = "导入失败，输入已保留：" + userFacingError(error) }
    }
    func discardImages() { if let id = session?.id { Task { await discardSession(id) } } }
    func priorReceipts(_ key: String) async throws -> [OrderImportReceipt] { try await db.read { try OrderImportReceipt.filter(sql: "sourceKey = ?", arguments: [key]).order(sql: "generation DESC").fetchAll($0) } }
    func existingItems() async throws -> [Item] { try await db.read { try Item.order(Item.Columns.name).fetchAll($0) } }
    private func apply(_ attributes: TaobaoImportAttributes) {
        brands = attributes.brands; categories = attributes.categories; alreadyImported = attributes.importedKeys
    }
}
