import SwiftUI
#if os(iOS)
@preconcurrency import UserNotifications
#endif

enum AppDeepLink: Equatable, Identifiable {
    case todayOutfit
    case payment(Int64)
    var id: String {
        switch self {
        case .todayOutfit: return "today-outfit"
        case .payment(let id): return "payment-\(id)"
        }
    }

    static func parse(_ url: URL) -> AppDeepLink? {
        guard url.scheme?.lowercased() == "lolita" else { return nil }
        if url.host == "today-outfit", url.path.isEmpty || url.path == "/" { return .todayOutfit }
        if url.host == "stage" {
            let parts = url.path.split(separator: "/")
            if parts.count == 1, let id = Int64(parts[0]), id > 0 { return .payment(-id) }
        }
        if url.host == "payment" {
            let parts = url.path.split(separator: "/")
            if parts.count == 1, let id = Int64(parts[0]), id > 0 { return .payment(id) }
        }
        return nil
    }
}

@MainActor
final class AppRouteState: ObservableObject {
    static let shared = AppRouteState()
    @Published var route: AppDeepLink?
    func open(_ url: URL) { if let parsed = AppDeepLink.parse(url) { route = parsed } }
}

struct PaymentNotificationDestination: View {
    let paymentId: Int64
    @State private var payment: Payment?
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let payment { PaymentEditScreen(priceId: payment.priceId, paymentId: payment.id) }
            else if let message {
                VStack(spacing: 16) {
                    Text(message).foregroundStyle(.secondary)
                    Button("关闭") { dismiss() }
                }.padding().lolitaNavBar(title: "付款提醒")
            } else { ProgressView("正在读取付款…") }
        }
        .task {
            do {
                payment = try await AppModule.shared.paymentRepository.getById(paymentId)
                if payment == nil { message = "这笔付款已被删除。" }
            } catch { message = userFacingError(error) }
        }
    }
}

#if os(iOS)
final class LolitaNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: value) else { return }
        await MainActor.run { AppRouteState.shared.open(url) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix("lolita.outfit.") {
            let repository = await MainActor.run {
                AppModule.shared.db == nil ? nil : AppModule.shared.outfitLogRepository
            }
            if let repository, (try? await repository.getForDay(containing: Date())) != nil { return [] }
        }
        return [.banner, .sound]
    }
}
#endif
