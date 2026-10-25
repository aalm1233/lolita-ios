import SwiftUI
import ImageIO
#if os(iOS)
import WebKit
import PhotosUI
#endif

@MainActor
final class ProductImportViewModel: ObservableObject {
    @Published var state = ProductImportSnapshot()
    @Published private(set) var session: OrderImportSession?
    @Published private(set) var photos: [String] = []
    @Published private(set) var details: [String] = []
    @Published private(set) var brands: [Brand] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var original: Item?
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var saved = false
    private let db: DatabaseQueue
    private let target: Int64?
    private var saveTail: Task<Void, Error>?
    private var ready = false
    private var generation = 0
    init(target: Int64?, db: DatabaseQueue = AppModule.shared.db.dbQueue) { self.target = target; self.db = db }
    private var repository: ProductImportRepository { ProductImportRepository(db: db) }
    var persistenceKey: String { (try? OrderImportSource.json(state) + OrderImportSource.json(photos) + OrderImportSource.json(details)) ?? "" }
    func load() async {
        guard !ready else { return }
        busy = true; defer { busy = false }
        do {
            let loaded = try await repository.load(target: target)
            session = loaded.session; state = loaded.snapshot; photos = loaded.photos; details = loaded.details
            let attrs = try await TaobaoImportRepository(db: db).attributes(); brands = attrs.brands; categories = attrs.categories
            if let target { original = try await ItemRepository(db: db).getById(target) }
            ready = true
        } catch { self.error = userFacingError(error) }
    }
    func persist() async -> Bool {
        guard ready, session != nil, !saved else { return true }
        let previous = saveTail
        let task = Task { @MainActor in
            if let previous { _ = try? await previous.value }
            guard let current = self.session else { return }
            self.session = try await self.repository.save(current, snapshot: self.state, photos: self.photos, details: self.details)
        }
        saveTail = task
        do { try await task.value; return true } catch { self.error = "商品草稿尚未保存：" + userFacingError(error); return false }
    }
    func accept(_ candidate: ProductCandidate) async {
        guard !busy else { return }
        busy = true; generation += 1; let request = generation
        defer { busy = false }
        state.candidate = candidate; state.name = candidate.name; state.properties = candidate.properties
        state.confirmedSKU = false
        // A reference price requires deliberate input even when the page displays a single value.
        var addedPhotos: [String] = [], addedDetails: [String] = [], owned: [String] = [], failures = 0
        do {
            for (values, isDetail) in [(candidate.photoURLs, false), (candidate.detailURLs, true)] {
                for raw in values.prefix(20) {
                    try Task.checkCancellation()
                    guard request == generation else { throw CancellationError() }
                    do {
                        let data = try await ProductImageDownloader.read(raw)
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0, width <= 16000, height <= 30000, width * height <= 50_000_000,
                              let path = ImageFileHelper.save(imageData: data) else { throw ValidationError.invalid("图片内容无效或过大") }
                        owned.append(path); if isDetail { addedDetails.append(path) } else { addedPhotos.append(path) }
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures += 1 }
                }
            }
            guard request == generation else { throw CancellationError() }
            photos += addedPhotos; details += addedDetails
            _ = await persist()
            if failures > 0 { error = "有 \(failures) 张网页图片未下载，已读取文字与成功图片保留；可重读网页或从相册补图。" }
        } catch {
            try? ImageFileHelper.deleteUnreferenced(paths: owned, db: db)
            if !(error is CancellationError) { self.error = userFacingError(error) }
        }
    }
    func refreshComparison() async {
        guard let target, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let comparison = try await db.read { db -> (Item, ItemDraft?) in
                guard let item = try Item.fetchOne(db, key: target) else { throw ValidationError.invalid("原物品已删除") }
                return (item, try ItemDraft.filter(sql: "targetItemId = ?", arguments: [target]).fetchOne(db))
            }
            original = comparison.0; state.baselineUpdatedAt = comparison.0.updatedAt
            state.baselineDraftHash = comparison.1.map(ProductSource.draftFingerprint)
            state.confirmedSKU = false; _ = await persist()
        } catch { self.error = userFacingError(error) }
    }
    func reloadDraft() async { ready = false; if let saveTail { _ = try? await saveTail.value }; await load() }
    func changeInput(_ value: String) {
        guard value != state.input else { return }
        generation += 1; state.input = value; state.candidate = nil; state.confirmedSKU = false
        photos = []; details = []
    }
    func manualCandidate() {
        guard let parsed = ProductSource.shareURL(state.input), let url = OrderImportSource.publicURL(parsed) else { error = "手动填写需要带商品 ID 的完整链接；短分享链接请先打开网页读取"; return }
        state.candidate = ProductCandidate(publicURL: url, warnings: ["手动填写资料，请确认本件颜色尺码和参考价"])
    }
    func addPhoto(_ data: Data, detail: Bool) async {
        #if os(iOS)
        guard !busy, let image = UIImage(data: data), let path = ImageFileHelper.save(image: image) else { error = "图片无法保存"; return }
        if detail { details.append(path) } else { photos.append(path) }
        _ = await persist()
        #endif
    }
    func removePhoto(_ path: String) { photos.removeAll { $0 == path }; details.removeAll { $0 == path } }
    func save() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard await persist(), let session else { return }
        let frozen = LoadedProductImport(session: session, snapshot: state, photos: photos, details: details)
        do { state = try await repository.commit(frozen); saved = true }
        catch { self.error = "保存失败，输入已保留：" + userFacingError(error) }
    }
    func discard() async -> Bool {
        if let saveTail { _ = try? await saveTail.value }
        guard let session else { return true }
        ready = false
        do { try await OrderImportSessionRepository(db: db).discard(session.id); try? ImageFileHelper.deleteUnreferenced(paths: photos + details, db: db); return true }
        catch { ready = true; self.error = userFacingError(error); return false }
    }
    func cancelReading() { generation += 1 }
}

import GRDB
private final class ProductImageDownloader: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(request.url.flatMap { ProductSource.imageURL($0.absoluteString) } == request.url ? request : nil) }
    static func read(_ raw: String) async throws -> Data {
        guard let url = ProductSource.imageURL(raw) else { throw ValidationError.invalid("不支持的商品图片地址") }
        let configuration = URLSessionConfiguration.ephemeral; configuration.httpShouldSetCookies = false; configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration, delegate: ProductImageDownloader(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), response.expectedContentLength <= 10 * 1024 * 1024, response.mimeType?.hasPrefix("image/") == true else { throw ValidationError.invalid("商品图片下载失败或超过 10 MB") }
        var data = Data()
        for try await byte in bytes { guard data.count < 10 * 1024 * 1024 else { throw ValidationError.invalid("商品图片超过 10 MB") }; data.append(byte) }
        return data
    }
}

struct ProductImportScreen: View {
    let targetItemId: Int64?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ProductImportViewModel
    @State private var showWeb = false
    @State private var showExit = false
    @State private var showReload = false
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    @State private var detailPhoto: PhotosPickerItem?
    #endif
    init(targetItemId: Int64? = nil) { self.targetItemId = targetItemId; _model = StateObject(wrappedValue: ProductImportViewModel(target: targetItemId)) }
    var body: some View {
        Form {
            if model.saved { result }
            else {
                Section("商品链接") {
                    TextField("粘贴淘宝／天猫商品链接或分享内容", text: Binding(get: { model.state.input }, set: { model.changeInput($0) })).accessibilityIdentifier("product-url")
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    Button("打开网页并读取") { if ProductSource.shareURL(model.state.input) == nil { model.error = "请提供带商品 ID 的完整淘宝／天猫链接" } else { showWeb = true } }.accessibilityIdentifier("product-open-web")
                    Button("重新读取已保存的商品草稿") { showReload = true }
                    Button("手动填写商品资料") { model.manualCandidate() }.accessibilityIdentifier("product-manual")
                    Text("网页读取只提供候选资料。链接登记进入心愿，参考价不会建立订单或付款。").font(.caption)
                }
                if let candidate = model.state.candidate {
                    Section("核对商品资料") {
                        ForEach(candidate.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        if !candidate.selectedSKU.isEmpty { Text("网页所选：" + candidate.selectedSKU) }
                        TextField("商品名称", text: $model.state.name).accessibilityIdentifier("product-name")
                        SearchableRecordPicker(title: "品牌", options: model.brands.map { PickerRecord(id: $0.id, name: $0.name) }, selection: $model.state.brandId).accessibilityIdentifier("product-brand")
                        SearchableRecordPicker(title: "分类", options: model.categories.map { PickerRecord(id: $0.id, name: $0.name) }, selection: $model.state.categoryId).accessibilityIdentifier("product-category")
                        TextField("颜色", text: $model.state.color)
                        TextField("尺码", text: $model.state.size)
                        TextField("商品参数", text: $model.state.properties, axis: .vertical).lineLimit(3...8)
                        if targetItemId == nil {
                            TextField("参考价（可留空，零元需填写 0）", text: $model.state.referenceText).accessibilityIdentifier("product-reference")
                            Text("例如：蓝色 | M | 120；每行一件，可省参考价并采用上方通用参考价。").font(.caption)
                            TextField("颜色 | 尺码 | 参考价（每行一件，可留空）", text: $model.state.variants, axis: .vertical).accessibilityIdentifier("product-variants")
                        }
                        Toggle("已确认本件颜色尺码及资料", isOn: $model.state.confirmedSKU).accessibilityIdentifier("product-confirm-sku")
                    }
                    if let item = model.original {
                        Section("与现有资料比较 · 仅采用勾选项") {
                            Button("重新读取现有资料进行比较") { Task { await model.refreshComparison() } }
                            Text("重新比较保留候选输入和图片，需再次确认后才能采用。").font(.caption)
                            Text("原名称：" + item.name); Text("原尺码：" + (item.size ?? "未设置")); Text("原颜色：" + item.colors.values.joined(separator: "、"))
                            Text("已有照片 \(item.imageUrls.values.count) 张、详情图 \(item.detailImagePaths.count) 张；新图片追加，保留原封面。")
                            if model.state.baselineDraftHash != nil { Text("存在编辑草稿，选用内容会合入原草稿，请在服饰编辑中最终保存。") }
                            ForEach([("name", "名称"), ("brand", "品牌"), ("category", "分类"), ("size", "尺码"), ("colors", "颜色"), ("properties", "追加商品参数"), ("photos", "追加照片"), ("details", "追加详情图")], id: \.0) { field, name in
                                Toggle("采用" + name, isOn: Binding(get: { model.state.selectedFields.contains(field) }, set: { if $0 { model.state.selectedFields.insert(field) } else { model.state.selectedFields.remove(field) } })).accessibilityIdentifier("product-apply-" + field)
                            }
                            Text("订单、实付、退款、状态、收纳和其他原资料会保留。").font(.caption)
                        }
                    }
                    imageSection
                }
            }
        }
        .disabled(model.busy)
        .lolitaNavBar(title: targetItemId == nil ? "商品链接登记" : "从商品链接补资料", showBack: true, onBack: { if model.saved { dismiss() } else { showExit = true } })
        .safeAreaInset(edge: .bottom) {
            if !model.saved { LolitaEditorSaveBar(title: model.busy ? "正在处理…" : targetItemId == nil ? "保存到心愿" : "采用所选资料", enabled: !model.busy && model.state.candidate != nil, identifier: "product-save") { Task { await model.save() } } }
        }
        #if os(iOS)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("product-dismiss-keyboard") } }
        #endif
        .task { await model.load() }
        .task(id: model.persistenceKey) { do { try await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled, !model.busy else { return }; _ = await model.persist() } catch {} }
        .sheet(isPresented: $showWeb) {
            #if os(iOS)
            if let url = ProductSource.shareURL(model.state.input) { ProductWebReaderScreen(url: url) { candidate in showWeb = false; Task { await model.accept(candidate) } } }
            #else
            Text("请在 iPhone 中读取商品网页")
            #endif
        }
        .confirmationDialog("重新读取会放弃尚未保存的输入，继续？", isPresented: $showReload, titleVisibility: .visible) {
            Button("重新读取已保存草稿") { Task { await model.reloadDraft() } }
            Button("继续编辑", role: .cancel) {}
        }
        .confirmationDialog("保存商品草稿后退出？", isPresented: $showExit, titleVisibility: .visible) {
            Button("保存草稿并退出") { Task { if await model.persist() { dismiss() } } }
            Button("放弃本次补资料", role: .destructive) { Task { if await model.discard() { dismiss() } } }
            Button("继续编辑", role: .cancel) {}
        } message: { Text("原物品、图片和账本会保留。") }
        .alert("商品资料", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("确定") { model.error = nil } } message: { Text(model.error ?? "") }
        .onDisappear { model.cancelReading(); Task { _ = await model.persist() } }
        #if os(iOS)
        .task(id: photo) { if let photo, let data = try? await photo.loadTransferable(type: Data.self), !Task.isCancelled { await model.addPhoto(data, detail: false); self.photo = nil } }
        .task(id: detailPhoto) { if let detailPhoto, let data = try? await detailPhoto.loadTransferable(type: Data.self), !Task.isCancelled { await model.addPhoto(data, detail: true); self.detailPhoto = nil } }
        #endif
    }
    @ViewBuilder private var imageSection: some View {
        Section("候选照片与详情图") {
            ForEach(model.photos + model.details, id: \.self) { path in HStack { LolitaThumbnail(path: path, width: 64, height: 72); Text(model.details.contains(path) ? "详情图" : "照片"); Spacer(); Button("移除", role: .destructive) { model.removePhoto(path) } } }
            #if os(iOS)
            PhotosPicker(selection: $photo, matching: .images) { SkinLabel("补充商品照片", systemImage: "photo.badge.plus") }
            PhotosPicker(selection: $detailPhoto, matching: .images) { SkinLabel("补充详情图", systemImage: "photo.badge.plus") }
            #endif
        }
    }
    @ViewBuilder private var result: some View {
        Section("保存完成") {
            Text(model.state.returnedDraftId == nil ? "资料和来源已保存" : "已合入原编辑草稿，尚未覆盖原物品")
            ForEach(model.state.savedItemIds, id: \.self) { id in NavigationLink("查看物品 #\(id)") { ItemDetailScreen(itemId: id) } }
            if model.state.returnedDraftId != nil, let targetItemId { NavigationLink("继续原服饰编辑") { ItemEditScreen(itemId: targetItemId) } }
            Button("完成") { dismiss() }
        }
    }
}

#if os(iOS)
@MainActor
private final class ProductWebController: ObservableObject {
    let web: WKWebView = {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private var pending: [UUID: CheckedContinuation<String, Error>] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private func finish(_ id: UUID, result: Result<String, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    private func snapshot() async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(7)) }
                    catch { return }
                    self?.finish(id, result: .failure(ValidationError.invalid("网页读取超时，请等待加载完成后重试")))
                }
                web.evaluateJavaScript(ProductSource.script) { [weak self] value, error in
                    let result: Result<String, Error>
                    if let error { result = .failure(error) }
                    else if let value = value as? String { result = .success(value) }
                    else { result = .failure(ValidationError.invalid("网页尚未就绪，请稍后重试")) }
                    Task { @MainActor in self?.finish(id, result: result) }
                }
            }
        } onCancel: { [weak self] in Task { @MainActor in self?.finish(id, result: .failure(CancellationError())) } }
    }
    func read(expected: String) async throws -> ProductCandidate {
        let a = try await snapshot(); try await Task.sleep(for: .milliseconds(300)); let b = try await snapshot()
        let first = try ProductSource.parse(a, expectedURL: expected), second = try ProductSource.parse(b, expectedURL: expected)
        guard first.publicURL == second.publicURL, first.selectedSKU == second.selectedSKU, first.priceText == second.priceText else { throw ValidationError.invalid("网页规格正在变化，请停止切换后重新读取") }
        return second
    }
}
private struct ProductWebView: UIViewRepresentable {
    let controller: ProductWebController
    let url: String
    func makeUIView(context: Context) -> WKWebView { controller.web.load(URLRequest(url: URL(string: url)!)); return controller.web }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: ()) { view.stopLoading() }
}
private struct ProductWebReaderScreen: View {
    let url: String
    let accept: (ProductCandidate) -> Void
    @StateObject private var controller = ProductWebController()
    @State private var error: String?
    @State private var reading = false
    @State private var readTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ProductWebView(controller: controller, url: url)
                .safeAreaInset(edge: .bottom) { VStack { Text("在网页选择颜色尺码后读取。登录仅保留在本次窗口，应用不读取账号或密码。").font(.caption).padding(.horizontal); Button(reading ? "正在读取…" : "读取当前商品资料") { reading = true; readTask = Task { do { let candidate = try await controller.read(expected: url); guard !Task.isCancelled else { return }; accept(candidate) } catch { if !Task.isCancelled { self.error = userFacingError(error) } }; reading = false } }.buttonStyle(.borderedProminent).disabled(reading).padding() } }
                .onDisappear { readTask?.cancel(); controller.web.stopLoading() }
                .lolitaNavBar(title: "读取商品资料")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { controller.web.stopLoading(); dismiss() } } }
                .alert("网页读取", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
#endif

struct ItemSourceHistoryView: View {
    let itemId: Int64
    @State private var records: [ItemSourceRecord] = []
    @State private var error: String?
    var body: some View {
        Group {
            if !records.isEmpty {
                LolitaSection(title: "来源资料") {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.kind.hasPrefix("taobao-order") ? "淘宝订单来源" : "商品资料来源").font(.headline)
                            if let raw = record.publicUrl, let url = URL(string: raw) { Link("查看公开商品链接", destination: url) }
                            if record.kind == "product-supplement-draft" { Text("选入编辑草稿的来源记录").font(.caption) }
                            if !record.appliedFields.values.isEmpty { Text("选用字段：" + record.appliedFields.values.map { ["name":"名称", "brand":"品牌", "category":"分类", "size":"尺码", "colors":"颜色", "properties":"商品参数", "photos":"照片", "details":"详情图"][$0] ?? "资料" }.joined(separator: "、")).font(.caption) }
                            Text(Date(timeIntervalSince1970: Double(record.createdAt) / 1000).formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task(id: itemId) {
            do { records = try await AppModule.shared.db.dbQueue.read { db in try ItemSourceRecord.filter(sql: "itemId = ?", arguments: [itemId]).order(sql: "createdAt DESC").fetchAll(db) } }
            catch { self.error = userFacingError(error) }
        }
    }
}

struct ImportedStorageScreen: View {
    let itemIds: [Int64]
    @State private var items: [Item] = []
    @State private var rooms: [Location] = []
    @State private var nodes: [StorageNode] = []
    @State private var selected = Set<Int64>()
    @State private var room: Int64?
    @State private var node: Int64?
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("仅安排本次新增且已拥有的物品") {
                ForEach(items, id: \.id) { item in Toggle(item.name, isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) }
                if items.isEmpty { Text("没有可安排收纳的已拥有物品") }
            }
            Section("放入位置") { StoragePlacementPicker(rooms: rooms, nodes: nodes, roomId: $room, nodeId: $node) }
        }
        .lolitaNavBar(title: "安排收纳")
        .task {
            do {
                let all = try await AppModule.shared.itemRepository.getAll(); items = all.filter { itemIds.contains($0.id) && $0.status == .owned }; selected = Set(items.map(\.id))
                rooms = try await AppModule.shared.locationRepository.getAll(); nodes = try await AppModule.shared.storageRepository.getAll()
            } catch { self.error = userFacingError(error) }
        }
        .safeAreaInset(edge: .bottom) {
            LolitaEditorSaveBar(title: "移入所选位置", enabled: !saving && !selected.isEmpty && room != nil, identifier: "import-storage-save") {
                let ids = selected, room = room, node = node; saving = true
                Task { do { try await AppModule.shared.storageRepository.placeImported(ids: ids, roomId: room, nodeId: node); dismiss() } catch { self.error = userFacingError(error) }; saving = false }
            }
        }
        .alert("安排收纳", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
    }
}
