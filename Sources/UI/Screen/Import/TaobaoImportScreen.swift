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
    @State private var removal: OrderImportFile?
    @State private var discardedSession: OrderImportSession?
    @State private var fileTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = viewModel.draftError {
                    LolitaCard {
                        VStack(spacing: 8) {
                            Text("草稿尚未保存：" + error).foregroundStyle(.red)
                            Button("重试保存会话") { Task { _ = await viewModel.saveDraft() } }
                            if let id = viewModel.session?.id { Button("重新读取已保存会话") { Task { await viewModel.restore(id) } } }
                        }
                    }
                }
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
        .task(id: viewModel.persistenceKey) {
            do { try await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled, !viewModel.isWorking else { return }; _ = await viewModel.saveDraft() } catch {}
        }
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
        .confirmationDialog("保存或放弃这次订单导入？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("保存会话并退出") { Task { if await viewModel.saveDraft() { dismiss() } } }
            Button("放弃导入", role: .destructive) { Task { if let id = viewModel.session?.id { if await viewModel.discardSession(id) { dismiss() } } else { dismiss() } } }
            Button("继续编辑", role: .cancel) {}
        } message: { Text("保存后可从导入会话继续；放弃只清理本会话，已提交的物品、订单和图片会保留。") }
        .confirmationDialog("移除文件及受影响的未提交编辑？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            Button("移除文件", role: .destructive) { if let id = removal?.id { viewModel.removeFile(id) }; removal = nil }
            Button("取消", role: .cancel) { removal = nil }
        } message: { Text("仅存在于此文件的商品编辑会被移除；已提交的物品和图片保留。") }
        .confirmationDialog("删除导入会话？", isPresented: Binding(get: { discardedSession != nil }, set: { if !$0 { discardedSession = nil } }), titleVisibility: .visible) {
            Button("删除会话", role: .destructive) { if let id = discardedSession?.id { Task { await viewModel.discardSession(id) } }; discardedSession = nil }
            Button("取消", role: .cancel) { discardedSession = nil }
        } message: { Text("已导入物品、付款、回执和图片都会保留。") }
        .confirmationDialog("确认导入 \(viewModel.importItemCount) 件服饰？", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("导入衣橱") { Task { await viewModel.executeImport() } }
            Button("继续检查", role: .cancel) {}
        } message: { Text("定金与尾款配对将合并为一件服饰，未勾选商品不会导入。原有衣橱会保留，已导入订单会自动去重。") }
        .alert("淘宝订单导入", isPresented: Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })) {
            Button("确定") { viewModel.error = nil }
        } message: { Text(viewModel.error ?? "") }
        .onDisappear {
            fileTask?.cancel()
            Task { _ = await viewModel.saveDraft() }
        }
    }

    private var selectionContent: some View {
        VStack(spacing: 12) {
            LolitaCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("从淘宝订单批量建立衣橱").font(.headline)
                    NavigationLink("通过商品链接登记心愿") { ProductImportScreen() }
                    Text("选择一个或多个 .xlsx 文件，检查商品、补全资料，再确认导入。默认勾选交易成功的商品，意向金和已导入订单不会自动勾选。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        SkinButton("选择 Excel 文件", systemImage: "doc.badge.plus") { showFilePicker = true }.buttonStyle(.borderedProminent)
                        Button("导入指南") { showGuide = true }.buttonStyle(.bordered)
                    }
                    if viewModel.fileCount > 0 {
                        Text("已读取 \(viewModel.fileCount) 个文件 · \(viewModel.orders.count) 个订单 · 重复订单 \(viewModel.duplicateOrders) 个")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !viewModel.sessions.isEmpty {
                LolitaCard { VStack(alignment: .leading, spacing: 12) {
                    Text("已保存的导入会话").font(.headline)
                    ForEach(viewModel.sessions) { session in
                        HStack {
                            Button("继续会话 " + Date(timeIntervalSince1970: Double(session.updatedAt) / 1000).formatted(date: .numeric, time: .shortened)) { Task { if await viewModel.saveDraft() { await viewModel.restore(session.id) } } }.accessibilityIdentifier("import-resume-" + session.id)
                            Spacer()
                            Button("删除", role: .destructive) { discardedSession = session }.accessibilityLabel("删除会话" + session.id)
                        }
                    }
                    Button("新建独立会话") { Task { await viewModel.newSession() } }.accessibilityIdentifier("import-new-session")
                } }
            }
            if !viewModel.files.isEmpty {
                LolitaCard { VStack(alignment: .leading, spacing: 10) {
                    Text("文件检查").font(.headline)
                    ForEach(viewModel.files) { file in
                        HStack { VStack(alignment: .leading) { Text(file.name); Text(file.problem ?? "已读取 \(file.orders.count) 个订单").font(.caption).foregroundStyle(file.problem == nil ? Color.secondary : Color.red) }; Spacer(); Button("移除") { removal = file } }
                    }
                } }
            }
            ForEach(viewModel.conflicts) { conflict in
                LolitaCard { VStack(alignment: .leading, spacing: 12) {
                    Text("来源冲突 · " + conflict.orderId).font(.headline)
                    Text("同一订单存在不同来源，请明确选择。本次选择不会覆盖以前导入的物品。")
                    ForEach(Array(conflict.versions.enumerated()), id: \.offset) { index, version in
                        Button("使用来源 \(index + 1) · \(version.orderStatus) · 实付 \(version.rawPaid ?? "未知") · 邮费 \(version.rawShipping ?? "未知") · \(version.items.count) 行") { viewModel.chooseSource(orderId: conflict.orderId, hash: OrderImportSource.snapshot(version)) }.accessibilityIdentifier("import-source-\(index)")
                        Text(version.items.map { $0.name + " ×" + String($0.quantity) }.joined(separator: "、")).font(.caption)
                    }
                } }
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
                                        if viewModel.alreadyImported.contains(item.id) { Text("旧版导入记录，请核对并关联现有物品").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                .toggleStyle(.checkboxCompatible)

                            }
                        }
                    }
                }
                Button("下一步：补全资料") { viewModel.prepare() }
                    .buttonStyle(.borderedProminent).disabled(viewModel.selectedKeys.isEmpty || !viewModel.conflicts.isEmpty)
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
                            SkinIcon(systemName: draft.included ? "checkmark.circle.fill" : "circle").frame(width: 32, height: 44)
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
                                SkinIcon(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier(draft.name)
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
                SkinIcon(systemName: "checkmark.circle.fill", size: 56).foregroundStyle(.tint)
                Text("成功导入 \(viewModel.result?.importedCount ?? 0) 件服饰").font(.title2.bold())
                Text("定金尾款合并 \(viewModel.result?.mergedCount ?? 0) 件 · 已导入去重 \(viewModel.result?.duplicateCount ?? 0) 条 · 未勾选 \(viewModel.result?.omittedCount ?? 0) 条")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("来源回执已与订单原子保存，重复提交会返回同一结果。").font(.caption)
                if let commit = viewModel.result?.commitId { Text("回执：" + commit).font(.caption).textSelection(.enabled) }
                Text("关联现有物品 \(viewModel.result?.linkedCount ?? 0) 件")
                ForEach(viewModel.result?.itemIds ?? [], id: \.self) { id in NavigationLink("查看本次新增 #\(id)") { ItemDetailScreen(itemId: id) } }
                NavigationLink("为本次已拥有物品安排收纳") { ImportedStorageScreen(itemIds: viewModel.result?.itemIds ?? []) }
                Button("继续处理剩余商品") { viewModel.resumeRemaining() }
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
    @State private var existingItems: [Item] = []
    @State private var priorReceipts: [OrderImportReceipt] = []
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
                    TextField("商品金额（不含邮费）", text: binding(\.priceText, fallback: ""))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("分摊邮费", text: binding(\.shippingText, fallback: ""))
                    TextField("真实实付", text: binding(\.paidText, fallback: ""))
                    TextField("实际付款日期（可留空）", text: binding(\.purchaseDate, fallback: ""))
                    Text("下单时间：" + draft.original.orderTime + "；未填写实付日期会保留为未知日期。").font(.caption)
                    Toggle("已核对商品金额、邮费和实付", isOn: binding(\.financialConfirmed, fallback: false))

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
                    PhotosPicker(selection: $photo, matching: .images) { SkinLabel(draft.imagePath == nil ? "补充图片" : "更换图片", systemImage: "photo.badge.plus") }
                    #else
                    Text("可在 iPhone 上选择照片补图").foregroundStyle(.secondary)
                    #endif
                }
                Section("来源身份核对") {
                    Text("本次商品金额 \(draft.priceText)，实付 \(draft.paidText)，邮费 \(draft.shippingText)")
                    ForEach(priorReceipts) { receipt in
                        Text("历史来源 · 代次 \(receipt.generation) · 物品 \(receipt.itemId.map(String.init) ?? "已删除") · 实付 \(OrderImportSource.amount(receipt.paidCents)) · 邮费 \(OrderImportSource.amount(receipt.shippingCents))")
                        Text(receipt.sourceSnapshot == draft.sourceSnapshotHash ? "来源与历史一致" : "来源内容与历史不同，请比较后确认").foregroundStyle(.orange)
                    }
                    Text("已导入的同一来源会返回原回执；来源变更必须确认，原物品不被覆盖。")
                    Toggle("已比较并确认来源身份", isOn: binding(\.identityConfirmed, fallback: false))
                    Toggle("原物品已删除，确认重新导入", isOn: binding(\.allowDeletedReimport, fallback: false))
                    Text("关联已有物品不会新建或修改付款；核对的份额仅登记来源占用，避免后续重复分摊。").font(.caption)
                    Picker("关联已有物品（不新建账本）", selection: binding(\.linkedItemId, fallback: nil)) {
                        Text("新建物品").tag(Int64?.none)
                        ForEach(existingItems, id: \.id) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                }
                Section("原订单") {
                    LabeledContent("订单号", value: draft.original.orderId)
                    LabeledContent("店铺", value: draft.original.shopName)
                    LabeledContent("数量", value: String(draft.original.quantity))
                    Text("同一来源数量按件展开；金额按全部源商品分摊，未勾选商品保留其份额。").font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: draft.original.productURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Link("查看商品链接", destination: url)
                    }
                }
            }
        }
        .disabled(viewModel.isWorking)
        .task { existingItems = (try? await viewModel.existingItems()) ?? []; priorReceipts = (try? await viewModel.priorReceipts(id)) ?? [] }
        .lolitaNavBar(title: "确认商品")
        #if os(iOS)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("import-dismiss-keyboard") } }
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { Task { if await viewModel.saveDraft() { dismiss() } } } } }
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
                        Text("文件按摘要去重，同订单的不同内容需明确选择来源。商品按稳定来源和件号去重，删除物品后重新导入需单独确认。")
                        Text("交易成功的订单默认选中。文件中出现退款、关闭或未付款订单时，请核对后自行选择；请逐件确认分摊邮费和真实实付，未知付款日期可留空，下单时间不会自动成为实付日期。")
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
                SkinIcon(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint).frame(width: 28, height: 44)
                configuration.label.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private extension ToggleStyle where Self == TaobaoCheckboxToggleStyle {
    static var checkboxCompatible: TaobaoCheckboxToggleStyle { TaobaoCheckboxToggleStyle() }
}
