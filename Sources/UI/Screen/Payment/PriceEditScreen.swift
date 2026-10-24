import SwiftUI

struct PriceEditScreen: View {
    @State private var saveError: String?
    @State private var adoptReference = false
    @State private var showDiscard = false
    @State private var proposedType: PriceType?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PriceEditViewModel

    init(itemId: Int64, priceId: Int64? = nil) {
        _viewModel = StateObject(wrappedValue: PriceEditViewModel(itemId: itemId, priceId: priceId))
    }

    var body: some View {
        Form {
            if let error = viewModel.loadError { Section { Text(error).foregroundStyle(.red) } }
            if viewModel.priceId == nil, viewModel.reference != nil {
                Button("采用独立参考价到草稿") { adoptReference = true }
            }
            Section("购买订单") {
                Picker("付款方式", selection: Binding(get: { viewModel.type }, set: { proposedType = $0 })) {
                    ForEach(PriceType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if viewModel.type != .depositBalance { moneyField("应付总额（含邮费）", text: $viewModel.totalPriceText) }
                else {
                    moneyField("定金", text: $viewModel.depositText)
                    moneyField("尾款", text: $viewModel.balanceText)
                }
                moneyField("其中邮费", text: $viewModel.shippingText)
                if viewModel.priceId == nil {
                    Text("建立订单会将心愿转为待付款。付款阶段是计划，真实付款请另行记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach($viewModel.stages) { $stage in
                Section(stageTitle(stage)) {
                    if viewModel.type == .multiStage {
                        TextField("阶段名称", text: $stage.name)
                        moneyField("阶段金额", text: $stage.amountText)
                    }
                    Toggle("指定应付日期", isOn: $stage.hasDueDate)
                    if stage.hasDueDate {
                        DatePicker("应付日期", selection: $stage.dueDate, displayedComponents: .date)
                        Toggle("提醒我付款", isOn: $stage.reminderSet)
                        if stage.reminderSet { Stepper("提前 \(stage.reminderDays) 天", value: $stage.reminderDays, in: 0...365) }
                    } else { Text("日期待定，不会自动生成到期日或提醒。").font(.caption).foregroundStyle(.secondary) }
                    if viewModel.type == .multiStage, viewModel.stages.count > 1 {
                        Button("移除本阶段", role: .destructive) { viewModel.stages.removeAll { $0.id == stage.id } }
                    }
                }
            }
            if viewModel.type == .multiStage {
                Button("添加阶段", systemImage: "plus") { viewModel.stages.append(PaymentStageInput()) }
            }
        }
        .disabled(viewModel.isSaving || !viewModel.isLoaded)
        .safeAreaInset(edge: .bottom) {
            LolitaEditorSaveBar(title: viewModel.isSaving ? "保存中…" : "保存订单",
                                enabled: !viewModel.isSaving && viewModel.isLoaded, identifier: "save-order") {
                Task { do { try await viewModel.save(); dismiss() } catch { saveError = userFacingError(error) } }
            }
        }
        .lolitaNavBar(title: viewModel.priceId == nil ? "建立购买订单" : "编辑订单计划", showBack: true, onBack: {
            if viewModel.hasChanges { showDiscard = true } else { dismiss() }
        })
        .interactiveDismissDisabled(viewModel.hasChanges || viewModel.isSaving)
        .confirmationDialog("用参考价填写全款草稿？只有保存订单后才建立购买，不会自动生成实付。", isPresented: $adoptReference) {
            Button("采用参考价") { viewModel.adoptReference() }
        }
        .confirmationDialog("切换付款方式会调整阶段，已付记录始终保留。", isPresented: Binding(get: { proposedType != nil }, set: { if !$0 { proposedType = nil } })) {
            Button("切换付款方式") { if let proposedType { viewModel.changeType(proposedType) }; proposedType = nil }
        }
        .confirmationDialog("放弃未保存的订单修改？", isPresented: $showDiscard) { Button("放弃修改", role: .destructive) { dismiss() } }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .task { await viewModel.load() }
    }

    private func stageTitle(_ stage: PaymentStageInput) -> String {
        if viewModel.type == .multiStage { return "付款阶段" }
        if viewModel.type == .full { return "全款计划" }
        return stage.id == viewModel.stages.first?.id ? "定金计划" : "尾款计划"
    }
    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
        #if os(iOS)
            .keyboardType(.decimalPad)
        #endif
    }
}
