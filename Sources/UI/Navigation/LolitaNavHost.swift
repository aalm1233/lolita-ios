import SwiftUI

enum Tab: String, CaseIterable {
    case items = "服饰"
    case wishlist = "愿望单"
    case outfits = "穿搭"
    case stats = "统计"
    case settings = "设置"
}

@available(iOS 16.0, macOS 13.0, *)
struct LolitaNavHost: View {
    @State private var selectedTab: Tab = .items

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ItemListScreen()
            }
            .tabItem {
                Image(systemName: selectedTab == .items ? "tshirt.fill" : "tshirt")
                Text(Tab.items.rawValue)
            }
            .tag(Tab.items)

            NavigationStack {
                WishlistScreen()
            }
            .tabItem {
                Image(systemName: selectedTab == .wishlist ? "heart.fill" : "heart")
                Text(Tab.wishlist.rawValue)
            }
            .tag(Tab.wishlist)

            NavigationStack {
                CoordinateListScreen()
            }
            .tabItem {
                Image(systemName: selectedTab == .outfits ? "figure.2.arms.open" : "figure.2")
                Text(Tab.outfits.rawValue)
            }
            .tag(Tab.outfits)

            NavigationStack {
                StatsPageScreen()
            }
            .tabItem {
                Image(systemName: selectedTab == .stats ? "chart.bar.fill" : "chart.bar")
                Text(Tab.stats.rawValue)
            }
            .tag(Tab.stats)

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Image(systemName: selectedTab == .settings ? "gearshape.fill" : "gearshape")
                Text(Tab.settings.rawValue)
            }
            .tag(Tab.settings)
        }
    }
}

/// Placeholder for unimplemented tabs (Phase 2)
struct PlaceholderScreen: View {
    let title: String
    var body: some View {
        VStack {
            Text(title)
                .font(.title)
                .foregroundStyle(.secondary)
            Text("即将推出")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
