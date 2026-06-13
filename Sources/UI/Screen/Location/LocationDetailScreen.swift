import SwiftUI

struct LocationDetailScreen: View {
    @StateObject private var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skinManager: SkinManager

    init(locationId: Int64) {
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(locationId: locationId))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Location image
                if let imageUrl = viewModel.location?.imageUrl {
                    LolitaShimmerImage(url: ImageFileHelper.fileURL(for: imageUrl))
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM))
                }

                // Name and description card
                LolitaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.location?.name ?? "")
                            .font(.title2.weight(.bold))
                        if let desc = viewModel.location?.description, !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Stored items section
                if !viewModel.items.isEmpty {
                    LolitaSection(title: "存放物品") {
                        ForEach(viewModel.items, id: \.id) { item in
                            NavigationLink {
                                Text(item.name)
                            } label: {
                                ItemRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(
            title: viewModel.location?.name ?? "位置详情",
            showBack: true,
            onBack: { dismiss() }
        )
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink("编辑") {
                    LocationEditScreen(
                        locationId: viewModel.locationId,
                        onSave: { await viewModel.load() }
                    )
                }
            }
        }
        #endif
        .task { await viewModel.load() }
    }
}
