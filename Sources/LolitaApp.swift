import SwiftUI

@main
@available(iOS 17.0, macOS 14.0, *)
struct LolitaApp: App {
    @StateObject private var skinManager = SkinManager()
    @State private var isReady = false
    @State private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @UIApplicationDelegateAdaptor(LolitaNotificationDelegate.self) private var notificationDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    LolitaNavHost()
                } else if let startupError {
                    VStack(spacing: 16) {
                        Text("无法打开衣橱").font(.headline)
                        Text(startupError).foregroundStyle(.secondary)
                        Button("重试") { Task { await initialize() } }
                    }.padding()
                } else {
                    ProgressView("正在准备衣橱…")
                }
            }
            .environmentObject(skinManager)
            .onOpenURL { AppRouteState.shared.open($0) }
            .task { await initialize() }
            .onChange(of: scenePhase) { _, phase in
                if isReady, phase == .active {
                    OutfitActivityCoordinator.shared.refresh()
                    Task { _ = await AppModule.shared.paymentReminderService.synchronize() }
                }
            }
        }
    }

    @MainActor
    private func initialize() async {
        guard !isReady else { return }
        startupError = nil
        do {
            if AppModule.shared.db == nil { try AppModule.shared.setupDatabase() }
            try await AppModule.shared.seedIfNeeded()
            OutfitActivityCoordinator.shared.start(db: AppModule.shared.db.dbQueue)
            AppModule.shared.paymentReminderService.start()
            isReady = true
        } catch {
            startupError = error.localizedDescription
        }
    }
}
