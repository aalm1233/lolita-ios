import SwiftUI

struct PaymentEditScreen: View {
    @State private var saveError: String?
    @State private var showDiscard = false
    @State private var savedWarning: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel: PaymentEditViewModel

    init(priceId: Int64, paymentId: Int64? = nil) {
        _viewModel = StateObject(wrappedValue: PaymentEditViewModel(priceId: priceId, paymentId: paymentId))
    }

    var body: some View {
        Form {
            Section {
                TextField("金额", text: $viewModel.amountText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                if !viewModel.isOrderPayment {
                    DatePicker("到期日", selection: $viewModel.dueDate, displayedComponents: .date)
                    Toggle("已支付", isOn: $viewModel.isPaid)
                }
                if viewModel.isOrderPayment {
                    Picker("归属阶段", selection: $viewModel.stageId) {
                        Text("不指定（按顺序抵扣）").tag(nil as Int64?)
                        ForEach(viewModel.stages) { Text($0.name).tag($0.id as Int64?) }
                    }
                }
                if viewModel.isPaid {
                    if viewModel.allowsUnknownDate { Toggle("历史付款日期未知", isOn: $viewModel.unknownPaidDate) }
                    if !viewModel.unknownPaidDate { DatePicker("真实付款日期", selection: $viewModel.paidDate, displayedComponents: .date) }
                }
            } header: {
                Text("付款信息")
            }
            if !viewModel.isPaid {
                Section {
                    Toggle("设置付款提醒", isOn: $viewModel.reminderSet)
                    if viewModel.reminderSet {
                        HStack {
                            Text("提前天数")
                            Spacer()
                            TextField("1", text: $viewModel.reminderDaysText)
#if os(iOS)
                                .keyboardType(.numberPad)
#endif
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                            Text("天").foregroundStyle(.secondary)
                        }
                    }
                    if let warning = viewModel.reminderWarning {
                        Label(warning, systemImage: "exclamationmark.bubble")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: { Text("提醒设置") } footer: {
                    Text("提前天数可填写 0 至 365。系统日历联动可在个人页开启；已支付或删除后会取消提醒。")
                }
            }
            if let error = viewModel.loadError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
        }
        .disabled(viewModel.isSaving || !viewModel.isLoaded)
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .alert("付款已保存", isPresented: Binding(get: { savedWarning != nil }, set: { if !$0 { savedWarning = nil } })) {
            Button("确定") { savedWarning = nil; dismiss() }
        } message: { Text(savedWarning ?? "") }
        .lolitaNavBar(title: viewModel.paymentId == nil ? "记录真实付款" : "更正付款", showBack: true, onBack: {
            if viewModel.hasChanges { showDiscard = true } else { dismiss() }
        })
        .interactiveDismissDisabled(viewModel.hasChanges || viewModel.isSaving)
        .confirmationDialog("放弃未保存的付款输入？", isPresented: $showDiscard) {
            Button("放弃修改", role: .destructive) { dismiss() }
        }
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        do {
                            if let warning = try await viewModel.save() { savedWarning = warning }
                            else { dismiss() }
                        } catch { saveError = userFacingError(error) }
                    }
                }
                .disabled(viewModel.isSaving || !viewModel.isLoaded || viewModel.loadError != nil)
            }
        }
#endif
        .task { await viewModel.load() }
        .onChange(of: viewModel.reminderSet) { _, enabled in
            if enabled { Task { await viewModel.requestReminderPermission() } }
        }
    }
}
