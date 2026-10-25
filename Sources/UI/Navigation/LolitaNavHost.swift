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
                SkinImages.image(key: "Home", skin: skinManager.currentSkinType)
                Text(Tab.items.rawValue)
            }
            .tag(Tab.items)

            NavigationStack {
                OutfitLogListScreen()
            }
            .tabItem {
                SkinImages.image(key: "Outfit", skin: skinManager.currentSkinType)
                Text(Tab.outfits.rawValue)
            }
            .tag(Tab.outfits)

            NavigationStack {
                StatsPageScreen()
            }
            .tabItem {
                SkinImages.image(key: "Stats", skin: skinManager.currentSkinType)
                Text(Tab.stats.rawValue)
            }
            .tag(Tab.stats)

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                SkinImages.image(key: "Settings", skin: skinManager.currentSkinType)
                Text(Tab.settings.rawValue)
            }
            .tag(Tab.settings)
        }
        .tint(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor)
        .font(.body)
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
