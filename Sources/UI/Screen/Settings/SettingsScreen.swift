import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        List {
            NavigationLink("品牌管理") {
                BrandManageScreen()
            }
            NavigationLink("分类管理") {
                CategoryManageScreen()
            }
            NavigationLink("风格管理") {
                StyleManageScreen()
            }
            NavigationLink("季节管理") {
                SeasonManageScreen()
            }
            NavigationLink("主题选择") {
                ThemeSelectScreen()
            }
        }
        .lolitaNavBar(title: "设置")
    }
}
