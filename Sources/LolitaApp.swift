import SwiftUI

@main
struct LolitaApp: App {
    @StateObject private var skin = DefaultSkin()

    var body: some Scene {
        WindowGroup {
            Text("Lolita iOS")
                .environmentObject(skin)
                .task {
                    try? await AppModule.shared.initialize()
                }
        }
    }
}
