import SwiftUI

/// Tab root screens use one compact header; detail screens keep their system back bar.
struct LolitaRootToolbar<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) { actions() }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

/// Keep the title, back action and screen actions in the same system navigation bar.
private struct LolitaNavigationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var skinManager: SkinManager

    let title: String
    let isHidden: Bool
    let showBack: Bool
    let onBack: (() -> Void)?

    private var background: Color {
        colorScheme == .dark ? skinManager.current.backgroundColorDark : skinManager.current.backgroundColor
    }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(background.ignoresSafeArea())
            .tint(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(showBack && onBack != nil)
            .toolbar(isHidden ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(LinearGradient(colors: colorScheme == .dark ? skinManager.current.gradientColorsDark : skinManager.current.gradientColors,
                                              startPoint: .leading, endPoint: .trailing), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if showBack, let onBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("返回")
                    }
                }
            }
            #endif
    }
}

extension View {
    func lolitaNavBar(title: String, isHidden: Bool = false, showBack: Bool = false, onBack: (() -> Void)? = nil) -> some View {
        modifier(LolitaNavigationModifier(title: title, isHidden: isHidden, showBack: showBack, onBack: onBack))
    }
}
