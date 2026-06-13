import SwiftUI

@main
@available(iOS 16.0, macOS 13.0, *)
struct LolitaApp: App {
    @StateObject private var skinManager = SkinManager()

    init() {
        try? AppModule.shared.setupDatabase()
    }

    var body: some Scene {
        WindowGroup {
            LolitaNavHost()
                .environmentObject(skinManager)
                .task {
                    try? await AppModule.shared.seedIfNeeded()
                }
        }
    }
}
