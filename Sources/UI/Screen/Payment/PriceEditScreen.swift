import SwiftUI

struct PriceEditScreen: View {
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel: PriceEditViewModel

    init(itemId: Int64, priceId: Int64? = nil) {
        _viewModel = StateObject(wrappedValue: PriceEditViewModel(itemId: itemId, priceId: priceId))
    }

    var body: some View {
        Form {
            Section {
                Picker("类型", selection: $viewModel.type) {
                    Text("全款").tag(PriceType.full)
                    Text("定金+尾款").tag(PriceType.depositBalance)
                }

                TextField("总价", text: $viewModel.totalPriceText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                if viewModel.type == .depositBalance {
                    TextField("定金", text: $viewModel.depositText)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    TextField("尾款", text: $viewModel.balanceText)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                }
                if viewModel.priceId == nil {
                    Toggle(viewModel.type == .full ? "已付全款" : "已付定金", isOn: $viewModel.initialPaid)
                    if viewModel.initialPaid { DatePicker("付款日期", selection: $viewModel.paymentDate, displayedComponents: .date) }
                    Text("保存后自动生成全款或定金/尾款付款记录，可在付款管理中调整到期日。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("价格信息")
            }
        }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .lolitaNavBar(title: viewModel.priceId == nil ? "添加价格" : "编辑价格", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        do {
                            try await viewModel.save()
                            dismiss()
                        } catch { saveError = userFacingError(error) }
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
#endif
        .task { await viewModel.load() }
    }
}
