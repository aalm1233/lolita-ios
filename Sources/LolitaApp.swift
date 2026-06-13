import SwiftUI

@main
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
