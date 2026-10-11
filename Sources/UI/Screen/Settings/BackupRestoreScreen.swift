import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupRestoreScreen: View {
    @State private var document: BackupDocument?
    @State private var exportType = UTType.json
    @State private var showExport = false
    @State private var showImport = false
    @State private var preview: BackupData?
    @State private var showPreview = false
    @State private var isWorking = false
    @State private var message: String?
    private var manager: BackupManager { BackupManager(db: AppModule.shared.db.dbQueue) }

    var body: some View {
        List {
            Section("导出") {
                Button("导出 JSON 备份（含图片）") { export(csv: false) }
                Button("导出服饰 CSV") { export(csv: true) }
            }
            Section("恢复") {
                Button("选择 JSON 备份") { showImport = true }
                Text("支持 iOS 备份和安卓 JSON 备份。安卓 JSON 若未包含图片，仅恢复文字与关联数据。恢复将替换当前衣橱，请先导出备份。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isWorking { ProgressView("正在处理…") }
        }
        .disabled(isWorking)
        .lolitaNavBar(title: "备份与恢复", showBack: true)
        .fileExporter(isPresented: $showExport, document: document, contentType: exportType,
                      defaultFilename: "lolita_\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .failure(let error) = result { message = userFacingError(error) }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                preview = try BackupManager.preview(Data(contentsOf: url))
                showPreview = true
            } catch { message = userFacingError(error) }
        }
        .confirmationDialog("确认恢复？", isPresented: $showPreview, titleVisibility: .visible) {
            Button("替换当前衣橱", role: .destructive) {
                guard let preview else { return }
                isWorking = true
                Task {
                    defer { isWorking = false; self.preview = nil }
                    do { try await manager.restore(preview); message = "恢复完成" }
                    catch { message = "恢复失败，原有数据已保留：\n" + userFacingError(error) }
                }
            }
            Button("取消", role: .cancel) { preview = nil }
        } message: {
            if let preview {
                Text("\(preview.items.count) 件服饰、\(preview.coordinates.count) 个套装、\(preview.outfitLogs.count) 条穿搭、\(preview.payments.count) 条付款。\n\(preview.imageData.count) 张内嵌图片；\(preview.missingImageCount) 个本地图片引用未随备份提供。")
            }
        }
        .alert("数据管理", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func export(csv: Bool) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                document = BackupDocument(data: try await (csv ? manager.exportCSV() : manager.exportJSON()))
                exportType = csv ? .commaSeparatedText : .json
                showExport = true
            } catch { message = userFacingError(error) }
        }
    }
}
