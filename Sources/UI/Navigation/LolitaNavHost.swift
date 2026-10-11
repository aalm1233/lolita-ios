import SwiftUI

enum Tab: String, CaseIterable {
    case items = "首页"
    case outfits = "穿搭"
    case stats = "统计"
    case settings = "个人"
}

@available(iOS 16.0, macOS 13.0, *)
struct LolitaNavHost: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .items
    @ObservedObject private var routeState = AppRouteState.shared

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
                OutfitLogListScreen()
            }
            .tabItem {
                Image(systemName: "figure.stand")
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
        .tint(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor)
        .font(skinManager.customFont ?? .body)
        .sheet(item: $routeState.route) { route in
            NavigationStack {
                switch route {
                case .todayOutfit: QuickOutfitLogScreen()
                case .payment(let id): PaymentNotificationDestination(paymentId: id)
                }
            }
            .environmentObject(skinManager)
        }
        #if os(iOS)
        .toolbarBackground(colorScheme == .dark ? skinManager.current.tabBarBackgroundColorDark : skinManager.current.tabBarBackgroundColor, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
    }
}
