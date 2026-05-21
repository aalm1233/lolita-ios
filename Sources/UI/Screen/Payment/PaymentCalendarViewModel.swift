import SwiftUI

@MainActor
final class PaymentCalendarViewModel: ObservableObject {
    @Published private(set) var paymentsByDate: [(date: Date, payments: [PaymentWithItemInfo])] = []
    @Published private(set) var totalUnpaid: Double = 0
    @Published private(set) var overdueAmount: Double = 0
    @Published var currentMonth: Date = Date()
    @Published private(set) var selectedDayPayments: [PaymentWithItemInfo]? = nil

    nonisolated(unsafe) private let paymentRepo = AppModule.shared.paymentRepository

    func load() {
        loadCalendar()
        Task {
            for await val in paymentRepo.getTotalUnpaidAmount() { totalUnpaid = val }
        }
        Task {
            for await val in paymentRepo.getOverdueAmount() { overdueAmount = val }
        }
    }

    func loadCalendar() {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(end.timeIntervalSince1970 * 1000)

        Task {
            for await payments in paymentRepo.getByDateRange(start: startMs, end: endMs) {
                let grouped = Dictionary(grouping: payments) { p in
                    let d = Date(timeIntervalSince1970: TimeInterval(p.dueDate) / 1000)
                    return cal.startOfDay(for: d)
                }
                paymentsByDate = grouped
                    .map { (date: $0.key, payments: $0.value) }
                    .sorted { $0.date < $1.date }
            }
        }
    }

    func selectDay(_ date: Date) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        selectedDayPayments = paymentsByDate.first(where: { cal.startOfDay(for: $0.date) == day })?.payments
    }

    func goToNextMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        loadCalendar()
    }

    func goToPreviousMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        loadCalendar()
    }

    var monthYearText: String {
        currentMonth.formatted(Date.FormatStyle().month(.wide).year())
    }

    func hasPayments(on day: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        return paymentsByDate.contains(where: { cal.startOfDay(for: $0.date) == d })
    }
}
