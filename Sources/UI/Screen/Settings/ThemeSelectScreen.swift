import SwiftUI

struct ThemeSelectScreen: View {
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        List {
            ForEach(SkinType.allCases, id: \.rawValue) { type in
                Button {
                    skinManager.`switch`(to: type)
                } label: {
                    HStack {
                        Text(type.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        if skinManager.currentSkinType == type {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .lolitaNavBar(title: "主题选择")
    }
}
