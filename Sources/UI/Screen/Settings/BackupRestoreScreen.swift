import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupRestoreScreen: View {
    private enum ExportFormat { case zip, json, csv }
    @State private var document: BackupDocument?
    @State private var exportType = UTType.zip
    @State private var showExport = false
    @State private var showImport = false
    @State private var preview: PreparedBackup?
    @State private var showPreview = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var restoreError: String?
    @State private var pendingRestoreMessage: String?
    private var manager: BackupManager { BackupManager(db: AppModule.shared.db.dbQueue) }

    var body: some View {
        List {
            Section("导出") {
                Button("导出 ZIP 备份（完整数据与图片）") { export(.zip) }
                Button("导出 JSON 备份（内嵌图片）") { export(.json) }
                Button("导出全部数据 CSV") { export(.csv) }
                Text("ZIP 保存全部衣橱记录、关联与本地图片，适合迁移和恢复。CSV 按品牌、服饰、付款、穿搭等表分段导出，供表格查看。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("恢复") {
                Button("选择 ZIP 或 JSON 备份") { showImport = true }
                Text("支持 iOS 备份和安卓衣橱备份。先预览记录与图片数量，再确认替换当前数据；请先保留一份备份。当前设备的头像、界面设置及日历授权会保留。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isWorking { ProgressView("正在处理…") }
        }
        .disabled(isWorking)
        .lolitaNavBar(title: "备份与恢复", showBack: true)
        .fileExporter(isPresented: $showExport, document: document, contentType: exportType,
                      defaultFilename: "lolita_\(Date().formatted(.iso8601.year().month().day()))") { result in
            document = nil
            if case .failure(let error) = result { message = userFacingError(error) }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.zip, .json]) { result in
            switch result {
            case .success(let url): importBackup(url)
            case .failure(let error): message = userFacingError(error)
            }
        }
        .sheet(isPresented: $showPreview, onDismiss: {
            preview = nil
            restoreError = nil
            if let pendingRestoreMessage {
                message = pendingRestoreMessage
                self.pendingRestoreMessage = nil
            }
        }) {
            if let preview { restorePreview(preview) }
        }
        .alert("数据管理", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func restorePreview(_ prepared: PreparedBackup) -> some View {
        NavigationStack {
            List {
                Section("备份信息") {
                    LabeledContent("格式", value: prepared.isZIP ? "ZIP（含图片）" : "JSON")
                    LabeledContent("备份时间", value: Date(timeIntervalSince1970: Double(prepared.backup.backupDate) / 1000)
                        .formatted(date: .numeric, time: .shortened))
                    LabeledContent("应用版本", value: prepared.backup.appVersion)
                }
                Section("数据预览") {
                    countRow("品牌", prepared.backup.brands.count)
                    countRow("分类", prepared.backup.categories.count)
                    countRow("服饰", prepared.backup.items.count)
                    countRow("套装", prepared.backup.coordinates.count)
                    countRow("位置", prepared.backup.locations.count)
                    countRow("风格", prepared.backup.styles.count)
                    countRow("季节", prepared.backup.seasons.count)
                    countRow("渠道", prepared.backup.sources.count)
                    countRow("价格", prepared.backup.prices.count)
                    countRow("付款", prepared.backup.payments.count)
                    countRow("穿搭", prepared.backup.outfitLogs.count)
                    countRow("穿搭关联", prepared.backup.outfitItemCrossRefs.count)
                    countRow("图片", prepared.imageCount)
                }
                if prepared.missingImageCount > 0 {
                    Section {
                        Text("此备份缺少 \(prepared.missingImageCount) 个本地图片引用。恢复后缺失图片将移除，请优先使用完整 ZIP 备份。")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Text("恢复将替换当前所有衣橱记录与关联。原设备的日历事件与通知注册不会复用，恢复后可在付款页重新开启提醒。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("确认替换当前衣橱", role: .destructive) { restore(prepared) }
                }
            }
            .disabled(isWorking)
            .overlay { if isWorking { ProgressView("正在恢复…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .lolitaNavBar(title: "确认恢复数据")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showPreview = false }.disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
        .alert("恢复失败", isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("确定") { restoreError = nil }
        } message: { Text(restoreError ?? "") }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        LabeledContent(title, value: "\(count) 条")
    }

    private func importBackup(_ url: URL) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    return try BackupManager.prepare(at: url)
                }.value
                restoreError = nil
                preview = prepared
                showPreview = true
            } catch { message = userFacingError(error) }
        }
    }

    private func restore(_ prepared: PreparedBackup) {
        isWorking = true
        restoreError = nil
        Task {
            defer { isWorking = false }
            do {
                try await manager.restore(prepared)
                pendingRestoreMessage = "恢复完成"
                showPreview = false
            } catch {
                restoreError = "原有数据已保留，可重试或取消：\n" + userFacingError(error)
            }
        }
    }

    private func export(_ format: ExportFormat) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let data: Data
                switch format {
                case .zip: data = try await manager.exportZIP(); exportType = .zip
                case .json: data = try await manager.exportJSON(); exportType = .json
                case .csv: data = try await manager.exportCSV(); exportType = .commaSeparatedText
                }
                document = BackupDocument(data: data)
                showExport = true
            } catch { message = userFacingError(error) }
        }
    }
}
