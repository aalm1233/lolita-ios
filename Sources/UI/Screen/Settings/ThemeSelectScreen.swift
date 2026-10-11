import SwiftUI

struct ThemeSelectScreen: View {
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("选择喜欢的配色，衣橱会立即更新。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SkinPreviewGrid(selectedType: skinManager.currentSkinType) { type in
                    skinManager.`switch`(to: type)
                }
            }
            .padding(16)
        }
        .lolitaNavBar(title: "主题选择", showBack: true)
    }
}

struct SkinPreviewGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selectedType: SkinType
    var onSelect: (SkinType) -> Void = { _ in }

    init(selectedType: SkinType, onSelect: @escaping (SkinType) -> Void = { _ in }) {
        self.selectedType = selectedType
        self.onSelect = onSelect
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SkinType.allCases, id: \.rawValue) { type in
                Button { onSelect(type) } label: {
                    SkinPreviewCard(type: type, isSelected: selectedType == type)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.displayName)
                .accessibilityValue(selectedType == type ? "当前主题" : "点按使用")
                .accessibilityAddTraits(selectedType == type ? .isSelected : [])
            }
        }
    }
}

struct SkinPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let type: SkinType
    let isSelected: Bool
    private let skin: any SkinProtocol

    init(type: SkinType, isSelected: Bool) {
        self.type = type
        self.isSelected = isSelected
        self.skin = SkinManager.create(type)
    }
    private var primary: Color { colorScheme == .dark ? skin.primaryColorDark : skin.primaryColor }
    private var card: Color { colorScheme == .dark ? skin.cardColorDark : skin.cardColor }
    private var background: Color { colorScheme == .dark ? skin.backgroundColorDark : skin.backgroundColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: colorScheme == .dark ? skin.gradientColorsDark : skin.gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(skin.topBarDecoration)
                        Spacer()
                        Image(systemName: "sparkles")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(primary.opacity(0.2))
                            .frame(width: 28, height: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(primary.opacity(0.35)).frame(width: 60, height: 5)
                            Capsule().fill(primary.opacity(0.16)).frame(width: 40, height: 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(card.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(type.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let colors = [primary, colorScheme == .dark ? skin.secondaryColorDark : skin.secondaryColor, background]
                    Circle()
                        .fill(colors[index])
                        .overlay(Circle().stroke(primary.opacity(0.2), lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                }
                Spacer(minLength: 4)
                Text(isSelected ? "已选择" : "点按使用")
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? primary : .secondary)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(primary)
                }
            }
        }
        .padding(12)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? primary : primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
