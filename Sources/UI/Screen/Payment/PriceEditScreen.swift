import SwiftUI

struct PriceEditScreen: View {
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
            } header: {
                Text("价格信息")
            }
        }
        .lolitaNavBar(title: viewModel.priceId == nil ? "添加价格" : "编辑价格", showBack: true)
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
