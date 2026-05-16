import SwiftUI

struct ThemeSelectScreen: View {
    @EnvironmentObject var skin: DefaultSkin

    let allSkins: [(name: String, available: Bool)] = [
        ("甜美粉", true),
        ("哥特暗黑", false),
        ("中华风韵", false),
        ("经典优雅", false),
        ("清风水手", false),
        ("田园牧歌", false),
        ("维多利亚", false),
    ]

    var body: some View {
        List {
            ForEach(allSkins, id: \.name) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    if item.available {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Text("Phase 2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.15)))
                    }
                }
                .opacity(item.available ? 1 : 0.5)
            }
        }
        .lolitaNavBar(title: "主题选择")
    }
}
