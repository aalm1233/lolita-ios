import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct TaobaoImportScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TaobaoImportViewModel()
    @State private var showFilePicker = false
    @State private var showGuide = false
    @State private var showDiscard = false
    @State private var showImportConfirmation = false
    @State private var editingItem: TaobaoEditingItem?
    @State private var fileTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if viewModel.isWorking { ProgressView("正在处理，请稍候…").frame(maxWidth: .infinity).padding() }
                switch viewModel.step {
                case .select: selectionContent
                case .prepare: preparationContent
                case .detail: detailContent
                case .result: resultContent
                }
            }
            .padding(12)
        }
        .disabled(viewModel.isWorking)
        .lolitaNavBar(title: "淘宝订单导入 · \(viewModel.step.rawValue)", showBack: true, onBack: back)
        .task { await viewModel.loadAttributes() }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                fileTask?.cancel()
                fileTask = Task { await viewModel.loadFiles(urls) }
            case .failure(let error): viewModel.error = userFacingError(error)
            }
        }
        .sheet(isPresented: $showGuide) { NavigationStack { TaobaoImportGuideScreen() } }
        .sheet(item: $editingItem) { item in
            NavigationStack { TaobaoImportItemEditor(viewModel: viewModel, id: item.id) }
        }
        .confirmationDialog("放弃这次订单导入？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃导入", role: .destructive) { viewModel.discardImages(); dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: { Text("已选择的订单和本次补充的图片将被清理，现有衣橱会保留。") }
        .confirmationDialog("确认导入 \(viewModel.importItemCount) 件服饰？", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("导入衣橱") { Task { await viewModel.executeImport() } }
            Button("继续检查", role: .cancel) {}
        } message: { Text("定金与尾款配对将合并为一件服饰，未勾选商品不会导入。原有衣橱会保留，已导入订单会自动去重。") }
        .alert("淘宝订单导入", isPresented: Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })) {
            Button("确定") { viewModel.error = nil }
        } message: { Text(viewModel.error ?? "") }
        .onDisappear {
            fileTask?.cancel()
        }
    }

    private var selectionContent: some View {
        VStack(spacing: 12) {
            LolitaCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("从淘宝订单批量建立衣橱").font(.headline)
                    Text("选择一个或多个 .xlsx 文件，检查商品、补全资料，再确认导入。默认勾选交易成功的商品，意向金和已导入订单不会自动勾选。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button("选择 Excel 文件", systemImage: "doc.badge.plus") { showFilePicker = true }.buttonStyle(.borderedProminent)
                        Button("导入指南") { showGuide = true }.buttonStyle(.bordered)
                    }
                    if viewModel.fileCount > 0 {
                        Text("已读取 \(viewModel.fileCount) 个文件 · \(viewModel.orders.count) 个订单 · 重复订单 \(viewModel.duplicateOrders) 个")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !viewModel.orders.isEmpty {
                HStack {
                    Text("已选 \(viewModel.selectedKeys.count) 件商品").font(.subheadline)
                    Spacer()
                    Button("全选") { viewModel.selectAll(true) }
                    Button("清空") { viewModel.selectAll(false) }
                }
                ForEach(viewModel.orders) { order in
                    LolitaCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(order.shopName.isEmpty ? "未提供店铺" : order.shopName).font(.headline); Spacer(); Text(order.orderStatus).font(.caption).foregroundStyle(.secondary) }
                            Text("\(order.orderId) · \(order.orderTime)").font(.caption).foregroundStyle(.secondary)
                            ForEach(order.items) { item in
                                Toggle(isOn: Binding(get: { viewModel.selectedKeys.contains(item.id) }, set: { selected in
                                    if selected { viewModel.selectedKeys.insert(item.id) } else { viewModel.selectedKeys.remove(item.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.subheadline)
                                        Text("\(item.styleSpec) · 数量 \(item.quantity) · ¥\(item.price.formatted(.number.precision(.fractionLength(2))))").font(.caption).foregroundStyle(.secondary)
                                        if viewModel.alreadyImported.contains(item.id) { Text("已导入").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                .toggleStyle(.checkboxCompatible)
                                .disabled(viewModel.alreadyImported.contains(item.id))
                            }
                        }
                    }
                }
                Button("下一步：补全资料") { viewModel.prepare() }
                    .buttonStyle(.borderedProminent).disabled(viewModel.selectedKeys.isEmpty)
            }
        }
    }

    private var preparationContent: some View {
        VStack(spacing: 12) {
            LolitaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("发现尚未建立的品牌和分类").font(.headline)
                    Text("勾选后会创建这些资料，再进入商品确认。未勾选的资料可在下一步手动选择现有品牌和分类。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(viewModel.missingAttributes.indices, id: \.self) { index in
                        Toggle(isOn: $viewModel.missingAttributes[index].included) {
                            HStack {
                                Text(viewModel.missingAttributes[index].name)
                                Spacer()
                                Text(viewModel.missingAttributes[index].kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkboxCompatible)
                    }
                }
            }
            HStack {
                Button("返回选择") { viewModel.backToSelection() }.buttonStyle(.bordered)
                Button("继续确认商品") { Task { await viewModel.confirmPrepare() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 12) {
            LolitaCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("检查商品与付款").font(.headline)
                    Text("点开商品可修改名称、品牌、分类、金额、购买日期和图片。自动配对可解除或手动调整；单独定金须补充待付尾款及截止日期。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("已勾选 \(viewModel.includedCount) 条订单商品，将建立 \(viewModel.importItemCount) 件服饰").font(.caption)
                }
            }
            ForEach(viewModel.drafts) { draft in
                LolitaCard(variant: .compact) {
                    HStack(alignment: .top, spacing: 10) {
                        Button { viewModel.setIncluded(!draft.included, for: draft.id) } label: {
                            Image(systemName: draft.included ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 32, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(draft.included ? "取消导入\(draft.name)" : "导入\(draft.name)")
                        Button { editingItem = TaobaoEditingItem(id: draft.id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                LolitaThumbnail(path: draft.imagePath, width: 64, height: 76)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(draft.role.rawValue) ¥\(draft.priceText) · \(draft.size) \(draft.color)").font(.caption).foregroundStyle(.secondary)
                                    Text(draft.pairedWith == nil ? (draft.role == .deposit ? "待填写尾款" : "独立导入") : "定金尾款已配对").font(.caption).foregroundStyle(.tint)
                                    if (draft.brandId == 0 || draft.categoryId == 0) && !(draft.role == .balance && draft.pairedWith != nil) { Text("请补全品牌和分类").font(.caption).foregroundStyle(.red) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("返回选择") { viewModel.backToSelection() }.buttonStyle(.bordered)
                Button("导入 \(viewModel.importItemCount) 件服饰") { showImportConfirmation = true }
                    .buttonStyle(.borderedProminent).disabled(viewModel.includedCount == 0)
            }
        }
    }

    private var resultContent: some View {
        LolitaCard {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.tint)
                Text("成功导入 \(viewModel.result?.importedCount ?? 0) 件服饰").font(.title2.bold())
                Text("定金尾款合并 \(viewModel.result?.mergedCount ?? 0) 件 · 已导入去重 \(viewModel.result?.duplicateCount ?? 0) 条 · 未勾选 \(viewModel.result?.omittedCount ?? 0) 条")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private func back() {
        guard !viewModel.isWorking else { return }
        if viewModel.hasUnsavedInput { showDiscard = true }
        else { dismiss() }
    }
}

private struct TaobaoEditingItem: Identifiable { let id: String }

private struct TaobaoImportItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TaobaoImportViewModel
    let id: String
    @State private var addingAttribute = false
    @State private var attributeKind: TaobaoMissingKind = .brand
    @State private var attributeName = ""
    @State private var attributeGroup: CategoryGroup = .clothing
    @State private var attributeError: String?
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif
    private var draft: TaobaoImportDraft? { viewModel.drafts.first { $0.id == id } }

    var body: some View {
        Form {
            if let draft {
                Section("商品资料") {
                    TextField("服饰名称", text: binding(\.name, fallback: ""))
                    SearchableRecordPicker(title: "品牌", options: viewModel.brands.map { PickerRecord(id: $0.id, name: $0.name) }, selection: binding(\.brandId, fallback: 0))
                    SearchableRecordPicker(title: "分类", options: viewModel.categories.map { PickerRecord(id: $0.id, name: $0.name) }, selection: binding(\.categoryId, fallback: 0))
                    HStack {
                        Button("新增品牌") { attributeKind = .brand; attributeName = ""; addingAttribute = true }
                        Spacer()
                        Button("新增分类") { attributeKind = .category; attributeName = ""; addingAttribute = true }
                    }
                    TextField("颜色", text: binding(\.color, fallback: ""))
                    TextField("尺码", text: binding(\.size, fallback: ""))
                    Text(draft.original.styleSpec).font(.caption).foregroundStyle(.secondary)
                }
                Section("付款信息") {
                    Picker("付款类型", selection: Binding(get: { self.draft?.role ?? .full }, set: { viewModel.setRole($0, for: id) })) {
                        ForEach(TaobaoPaymentRole.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("已付金额", text: binding(\.priceText, fallback: ""))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("购买日期 yyyy-MM-dd HH:mm", text: binding(\.purchaseDate, fallback: ""))
                    if draft.role != .full {
                        if let pair = draft.pairedWith, let partner = viewModel.drafts.first(where: { $0.id == pair }) {
                            LabeledContent("已配对", value: "\(partner.name) · ¥\(partner.priceText)")
                            Button("解除配对") { viewModel.unpair(id) }
                        } else {
                            Menu("选择\(draft.role == .deposit ? "尾款" : "定金")订单配对") {
                                ForEach(viewModel.drafts.filter { $0.id != id && $0.role != .full && $0.role != draft.role }) { partner in
                                    Button("\(partner.name) · ¥\(partner.priceText)") { viewModel.pair(id, with: partner.id) }
                                }
                            }
                            if draft.role == .deposit {
                                TextField("待付尾款", text: binding(\.manualBalanceText, fallback: ""))
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                DatePicker("尾款截止日期", selection: binding(\.balanceDueDate, fallback: Date()), displayedComponents: .date)
                            }
                        }
                    }
                }
                Section("商品照片") {
                    if let path = draft.imagePath {
                        LolitaThumbnail(path: path, width: 120, height: 150)
                        Button("移除图片", role: .destructive) { viewModel.removeImage(from: id) }
                    }
                    #if os(iOS)
                    PhotosPicker(selection: $photo, matching: .images) { Label(draft.imagePath == nil ? "补充图片" : "更换图片", systemImage: "photo.badge.plus") }
                    #else
                    Text("可在 iPhone 上选择照片补图").foregroundStyle(.secondary)
                    #endif
                }
                Section("原订单") {
                    LabeledContent("订单号", value: draft.original.orderId)
                    LabeledContent("店铺", value: draft.original.shopName)
                    LabeledContent("数量", value: String(draft.original.quantity))
                    Text("每条商品记录导入为一件服饰，金额取 Excel 中的商品金额；多数量订单请在确认金额时核对。").font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: draft.original.productURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Link("查看商品链接", destination: url)
                    }
                }
            }
        }
        .disabled(viewModel.isWorking)
        .lolitaNavBar(title: "确认商品")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $addingAttribute) {
            NavigationStack {
                Form {
                    TextField("\(attributeKind.rawValue)名称", text: $attributeName)
                    if attributeKind == .category {
                        Picker("分组", selection: $attributeGroup) {
                            Text("服装").tag(CategoryGroup.clothing)
                            Text("小物").tag(CategoryGroup.accessory)
                        }
                    }
                }
                .disabled(viewModel.isWorking)
                .lolitaNavBar(title: "新增\(attributeKind.rawValue)")
                .interactiveDismissDisabled(viewModel.isWorking)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { addingAttribute = false }.disabled(viewModel.isWorking) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let name = attributeName, kind = attributeKind, group = attributeGroup
                            Task {
                                do { try await viewModel.addAttribute(name: name, kind: kind, group: group, to: id); addingAttribute = false }
                                catch { attributeError = userFacingError(error) }
                            }
                        }.disabled(viewModel.isWorking)
                    }
                }
                .alert("新增资料", isPresented: Binding(get: { attributeError != nil }, set: { if !$0 { attributeError = nil } })) {
                    Button("确定") { attributeError = nil }
                } message: { Text(attributeError ?? "") }
            }
        }
        .alert("商品编辑", isPresented: Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })) {
            Button("确定") { viewModel.error = nil }
        } message: { Text(viewModel.error ?? "") }
        #if os(iOS)
        .task(id: photo) {
            guard let photo else { return }
            do {
                if let data = try await photo.loadTransferable(type: Data.self), !Task.isCancelled { viewModel.addImage(data, to: id) }
            } catch { if !Task.isCancelled { viewModel.error = "补图失败：" + userFacingError(error) } }
        }
        #endif
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaobaoImportDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { draft?[keyPath: keyPath] ?? fallback }, set: { value in
            guard !viewModel.isWorking, let index = viewModel.drafts.firstIndex(where: { $0.id == id }) else { return }
            viewModel.drafts[index][keyPath: keyPath] = value
        })
    }
}

struct TaobaoImportGuideScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LolitaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("准备订单 Excel").font(.headline)
                        Text("将淘宝导出的 .xlsx 订单文件保存到「文件」App，可一次选择多个文件。")
                        Text("文件首张工作表需包含以下 11 列：订单号、订单提交时间、订单状态、店铺名称、商品名称、商品链接、型号款式、商品数量、商品金额、实付金额、运费。")
                        Text("同一订单的后续商品行可省略订单号等订单资料，应用会沿用首行资料。支持 Excel 的合并单元格、共享字符串和直接文本。")
                    }
                }
                LolitaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("导入步骤").font(.headline)
                        Text("1. 选择文件，勾选需要导入的商品。")
                        Text("2. 确认自动识别的品牌和分类，并创建缺失资料。")
                        Text("3. 检查商品金额、日期、颜色和尺码，可从照片补充图片。")
                        Text("4. 核对定金尾款配对；未配对定金需要填写待付尾款和截止日期。")
                        Text("5. 确认导入，应用将同时保存服饰、价格和付款记录。")
                    }
                }
                LolitaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("去重与付款").font(.headline)
                        Text("重复文件按订单号去重，重复导入按订单中的商品序号去重。若修改过 Excel 商品顺序，请核对后再导入。")
                        Text("交易成功的订单默认选中。文件中出现退款、关闭或未付款订单时，请核对后自行选择；导入的商品金额会记录为已付款。")
                        Text("定金和已付尾款合并后为已拥有；只导入定金且仍有待付尾款的商品会显示待尾款。")
                    }
                }
            }.padding(12)
        }
        .lolitaNavBar(title: "淘宝订单导入指南")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

private struct TaobaoCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(.tint).frame(width: 28, height: 44)
                configuration.label.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private extension ToggleStyle where Self == TaobaoCheckboxToggleStyle {
    static var checkboxCompatible: TaobaoCheckboxToggleStyle { TaobaoCheckboxToggleStyle() }
}
