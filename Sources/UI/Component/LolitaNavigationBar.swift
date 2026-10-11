import SwiftUI

/// Keep the title, back action and screen actions in the same system navigation bar.
private struct LolitaNavigationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var skinManager: SkinManager

    let title: String
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
            .toolbarBackground(background, for: .navigationBar)
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
    func lolitaNavBar(title: String, showBack: Bool = false, onBack: (() -> Void)? = nil) -> some View {
        modifier(LolitaNavigationModifier(title: title, showBack: showBack, onBack: onBack))
    }
}
