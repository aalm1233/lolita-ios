import SwiftUI
@preconcurrency import GRDB
#if canImport(UIKit)
import UIKit
#endif

enum TaobaoImportStep: String { case select = "选择商品", prepare = "补全资料", detail = "确认商品", result = "导入完成" }

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

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        repository = TaobaoImportRepository(db: db)
    }

    deinit {
        // A tab change keeps the view model alive and must keep its edited photos.
        // When the import is actually released, only uncommitted, unreferenced files are removed.
        try? ImageFileHelper.deleteUnreferenced(paths: Array(temporaryImages), db: db)
    }

    var hasUnsavedInput: Bool { !orders.isEmpty && !committed }
    var includedCount: Int { drafts.filter(\.included).count }
    var importItemCount: Int {
        let included = drafts.filter(\.included)
        let keys = Set(included.map(\.id))
        return included.count - included.filter { $0.role == .balance && $0.pairedWith.map(keys.contains) == true }.count
    }

    func loadAttributes() async {
        do { apply(try await repository.attributes()) }
        catch { if !Task.isCancelled { self.error = userFacingError(error) } }
    }

    func loadFiles(_ urls: [URL]) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let worker = Task.detached(priority: .userInitiated) {
                guard !urls.isEmpty, urls.count <= 50 else { throw ValidationError.invalid("请选择 1 至 50 个文件") }
                var files: [Data] = []
                var totalBytes = 0
                for url in urls {
                    try Task.checkCancellation()
                    guard url.pathExtension.lowercased() == "xlsx" else { throw ValidationError.invalid("仅支持 .xlsx 格式的淘宝订单文件") }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= TaobaoOrderParser.maximumFileSize else { throw ValidationError.invalid("订单文件超过 32 MB，请分批导入") }
                    totalBytes += size
                    guard totalBytes <= 64 * 1024 * 1024 else { throw ValidationError.invalid("所选文件合计超过 64 MB，请分批导入") }
                    files.append(try Data(contentsOf: url))
                }
                return try TaobaoOrderParser.parseMultipleFiles(files)
            }
            let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            let attributes = try await repository.attributes()
            guard !Task.isCancelled else { return }
            discardImages()
            apply(attributes)
            orders = parsed.orders
            fileCount = parsed.fileCount
            duplicateOrders = parsed.duplicateCount
            selectedKeys = Set(parsed.orders.filter { $0.orderStatus == "交易成功" }.flatMap(\.items).filter { !$0.styleSpec.contains("意向金") && !alreadyImported.contains($0.id) }.map(\.id))
            drafts = []; missingAttributes = []; step = .select; result = nil; committed = false
        } catch {
            if !Task.isCancelled { self.error = "读取订单失败：" + userFacingError(error) }
        }
    }

    func selectAll(_ selected: Bool) {
        guard !isWorking else { return }
        selectedKeys = selected ? Set(orders.flatMap(\.items).filter { !alreadyImported.contains($0.id) }.map(\.id)) : []
    }

    func prepare() {
        guard !isWorking, !selectedKeys.isEmpty else { return }
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
        let built = orders.flatMap(\.items).filter { selectedKeys.contains($0.id) }.map { original -> TaobaoImportDraft in
            var draft = existing[original.id] ?? TaobaoImportDraft(original: original)
            if draft.brandId == 0 { draft.brandId = TaobaoImportMatching.brand(original.shopName, in: brands)?.id ?? 0 }
            if draft.categoryId == 0 { draft.categoryId = TaobaoImportMatching.category(original.parsedType, in: categories)?.id ?? 0 }
            return draft
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
        if let old = drafts[index].imagePath, temporaryImages.contains(old) { ImageFileHelper.delete(path: old); temporaryImages.remove(old) }
        temporaryImages.insert(path); drafts[index].imagePath = path
    }

    func removeImage(from id: String) {
        guard !isWorking, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        if let old = drafts[index].imagePath, temporaryImages.contains(old) { ImageFileHelper.delete(path: old); temporaryImages.remove(old) }
        drafts[index].imagePath = nil
    }

    func executeImport() async {
        guard !isWorking else { return }
        isWorking = true
        let snapshot = drafts
        defer { isWorking = false }
        do {
            result = try await repository.save(snapshot)
            // Committed images are protected by reference checks; paired/omitted images are removed.
            try? ImageFileHelper.deleteUnreferenced(paths: Array(temporaryImages), db: db)
            temporaryImages = []; committed = true; step = .result
        } catch { self.error = "导入失败，输入已保留：" + userFacingError(error) }
    }

    func discardImages() {
        guard !committed else { return }
        try? ImageFileHelper.deleteUnreferenced(paths: Array(temporaryImages), db: db)
        temporaryImages = []
    }

    private func apply(_ attributes: TaobaoImportAttributes) {
        brands = attributes.brands; categories = attributes.categories; alreadyImported = attributes.importedKeys
    }
}
