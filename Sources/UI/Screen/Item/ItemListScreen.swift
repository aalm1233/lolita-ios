import SwiftUI

struct ItemListScreen: View {
    @StateObject private var viewModel = ItemListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.selectedSubTab) {
                ForEach(ItemSubTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            TabView(selection: $viewModel.selectedSubTab) {
                locationTab.tag(ItemSubTab.location)
                itemsTab.tag(ItemSubTab.items)
                coordinateTab.tag(ItemSubTab.coordinate)
                catalogTab.tag(ItemSubTab.catalog)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .lolitaNavBar(title: "服饰")
        .onAppear { viewModel.load() }
    }

    private var locationTab: some View {
        List {
            ForEach(viewModel.locations, id: \.id) { location in
                NavigationLink {
                    LocationDetailScreen(locationId: location.id)
                } label: {
                    HStack {
                        if let url = location.imageUrl {
                            LolitaShimmerImage(url: ImageFileHelper.fileURL(for: url))
                                .frame(width: 44, height: 44)
                        }
                        Text(location.name)
                    }
                }
            }
        }
    }

    private var itemsTab: some View {
        List {
            ForEach(viewModel.itemsByStatus(.owned), id: \.id) { item in
                NavigationLink {
                    ItemDetailScreen(itemId: item.id)
                } label: {
                    ItemRow(item: item)
                }
            }
        }
    }

    private var coordinateTab: some View {
        List {
            ForEach(viewModel.coordinates, id: \.id) { coordinate in
                NavigationLink {
                    CoordinateDetailScreen(coordinateId: coordinate.id)
                } label: {
                    HStack(spacing: 12) {
                        if let firstUrl = coordinate.imageUrls.values.first {
                            LolitaShimmerImage(url: ImageFileHelper.fileURL(for: firstUrl))
                                .frame(width: 44, height: 44)
                        }
                        VStack(alignment: .leading) {
                            Text(coordinate.name).font(.body.weight(.medium))
                            Text(coordinate.description).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var catalogTab: some View {
        List {
            ForEach(viewModel.itemsByStatus(.owned), id: \.id) { item in
                NavigationLink {
                    ItemDetailScreen(itemId: item.id)
                } label: {
                    ItemRow(item: item)
                }
            }
        }
    }
}

// MARK: - Shared ItemRow (used by other screens)

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            if let firstUrl = item.imageUrls.values.first {
                LolitaShimmerImage(url: ImageFileHelper.fileURL(for: firstUrl))
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.medium))
                if let style = item.style {
                    Text(style)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
