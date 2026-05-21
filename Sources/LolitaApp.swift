import SwiftUI

@main
struct LolitaApp: App {
    @StateObject private var skin = DefaultSkin()

    init() {
        try? AppModule.shared.setupDatabase()
    }

    var body: some Scene {
        WindowGroup {
            if #available(iOS 16.0, macOS 13.0, *) {
                LolitaNavHost()
                    .environmentObject(skin)
                    .task {
                        try? await AppModule.shared.seedIfNeeded()
                    }
            } else {
                Text("Lolita iOS")
                    .environmentObject(skin)
                    .task {
                        try? await AppModule.shared.seedIfNeeded()
                    }
            }
        }
    }
}
