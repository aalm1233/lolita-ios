import SwiftUI

struct ReminderSettingsScreen: View {
    @ObservedObject private var paymentService = AppModule.shared.paymentReminderService
    @ObservedObject private var outfitService = OutfitActivityCoordinator.shared
    @AppStorage("outfitReminderEnabled") private var outfitEnabled = false
    @AppStorage("outfitReminderHour") private var hour = 20
    @AppStorage("outfitReminderMinute") private var minute = 0
    @State private var reminderTime = Date()
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("每日穿搭") {
                Toggle("每日穿搭提醒", isOn: Binding(get: { outfitEnabled }, set: { value in applyOutfit(enabled: value) }))
                DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .disabled(!outfitEnabled)
                    .onChange(of: reminderTime) { _, _ in if outfitEnabled { applyOutfit(enabled: true) } }
                Text("当天已有穿搭记录时不再提醒。打开应用会自动续期未来两周的提醒。")
                    .font(.caption).foregroundStyle(.secondary)
                if let issue = outfitService.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            }
            #if os(iOS)
            Section("付款") {
                Button("允许付款通知") {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        message = await AppModule.shared.paymentReminderService.requestNotificationAuthorization()
                        _ = await AppModule.shared.paymentReminderService.synchronize()
                    }
                }
                Text("每笔付款可在编辑页设置是否提醒及提前天数。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("同步未付提醒到系统日历", isOn: Binding(
                    get: { paymentService.calendarEnabled },
                    set: { enabled in
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            message = await AppModule.shared.paymentReminderService.setCalendarEnabled(enabled)
                        }
                    }))
                Text("同步开启提醒的未付日程；付款已付、删除或关闭同步后会移除对应日历事件。")
                    .font(.caption).foregroundStyle(.secondary)
                if let issue = paymentService.notificationWarning { Text(issue).font(.caption).foregroundStyle(.orange) }
                if let issue = paymentService.calendarWarning { Text(issue).font(.caption).foregroundStyle(.orange) }
            }
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Section { Link("打开系统设置", destination: url) }
            }
            #endif
        }
        .disabled(isSaving)
        .lolitaNavBar(title: "提醒与系统日历", showBack: true)
        .onAppear { reminderTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        .alert("提醒设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func applyOutfit(enabled: Bool) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        Task {
            isSaving = true
            defer { isSaving = false }
            message = await OutfitActivityCoordinator.shared.applyReminder(enabled: enabled, hour: components.hour ?? 20, minute: components.minute ?? 0)
        }
    }
}
