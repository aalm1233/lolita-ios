import SwiftUI

struct PaymentEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
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

                DatePicker("到期日", selection: $viewModel.dueDate, displayedComponents: .date)

                Toggle("已支付", isOn: $viewModel.isPaid)

                if viewModel.isPaid {
                    DatePicker("支付日期", selection: $viewModel.paidDate, displayedComponents: .date)
                }
            } header: {
                Text("付款信息")
            }
        }
        .lolitaNavBar(title: viewModel.paymentId == nil ? "添加付款" : "编辑付款", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        try? await viewModel.save()
                        dismiss()
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
#endif
        .task { await viewModel.load() }
    }
}
