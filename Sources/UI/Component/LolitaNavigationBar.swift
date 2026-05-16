import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LolitaNavigationBar: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var skin: DefaultSkin

    let title: String
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil

    private var isDark: Bool { colorScheme == .dark }
    private var gradient: [Color] { isDark ? skin.gradientColorsDark : skin.gradientColors }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea(edges: .top)

            HStack(spacing: 8) {
                if showBack {
                    Button(action: { onBack?() }) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }

                Text(skin.topBarDecoration)
                    .font(.system(size: 16))
                    .opacity(skin.topBarDecorationAlpha)
                    .foregroundColor(.white)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, skin.spacingL)
            .padding(.vertical, 12)
        }
        .frame(height: 44 + safeAreaTop)
    }

    private var safeAreaTop: CGFloat {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 0
        #else
        return 0
        #endif
    }
}

// MARK: - Convenience modifier

extension View {
    func lolitaNavBar(title: String, showBack: Bool = false, onBack: (() -> Void)? = nil) -> some View {
        VStack(spacing: 0) {
            LolitaNavigationBar(title: title, showBack: showBack, onBack: onBack)
            self
        }
    }
}
