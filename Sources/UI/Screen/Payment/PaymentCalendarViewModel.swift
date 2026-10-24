import SwiftUI

@MainActor
final class PaymentCalendarViewModel: ObservableObject {
    @Published private(set) var paymentsByDate: [(date: Date, payments: [PaymentWithItemInfo])] = []
    @Published private(set) var totalUnpaid: Double = 0
    @Published private(set) var overdueAmount: Double = 0
    @Published var currentMonth: Date = Date()
    @Published private(set) var selectedDayPayments: [PaymentWithItemInfo]?
    private var selectedDay: Date?
    private var monthTask: Task<Void, Never>?
    private var summaryTasks: [Task<Void, Never>] = []
    private let paymentRepo: PaymentRepository

    init(repository: PaymentRepository = AppModule.shared.paymentRepository) { paymentRepo = repository }

    func load() {
        loadCalendar()
        guard summaryTasks.isEmpty else { return }
        summaryTasks = [
            Task { [weak self, paymentRepo] in
                for await value in paymentRepo.getTotalUnpaidAmount() { guard !Task.isCancelled else { return }; self?.totalUnpaid = value }
            },
            Task { [weak self, paymentRepo] in
                for await value in paymentRepo.getOverdueAmount() { guard !Task.isCancelled else { return }; self?.overdueAmount = value }
            }
        ]
    }

    func stopObserving() {
        monthTask?.cancel()
        monthTask = nil
        summaryTasks.forEach { $0.cancel() }
        summaryTasks.removeAll()
    }

    func loadCalendar() {
        monthTask?.cancel()
        paymentsByDate = []
        selectedDay = nil
        selectedDayPayments = nil
        let month = currentMonth
        let cal = Calendar.current
        let range = PaymentMonthRange(month: month, calendar: cal)
        monthTask = Task { [weak self, paymentRepo] in
            for await payments in paymentRepo.getByDateRange(start: range.start, end: range.end) {
                guard !Task.isCancelled, let self, self.currentMonth == month else { return }
                let grouped = Dictionary(grouping: payments) {
                    cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.dueDate) / 1000))
                }
                self.paymentsByDate = grouped.map { (date: $0.key, payments: $0.value) }.sorted { $0.date < $1.date }
                if let selectedDay = self.selectedDay { self.selectDay(selectedDay) }
            }
        }
    }

    func selectDay(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        selectedDay = day
        selectedDayPayments = paymentsByDate.first(where: { $0.date == day })?.payments
    }

    func markPaid(_ value: PaymentWithItemInfo) async throws {
        try await paymentRepo.markPaid(value.paymentId)
    }

    func goToNextMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        loadCalendar()
    }

    func goToPreviousMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        loadCalendar()
    }

    var monthYearText: String { currentMonth.formatted(Date.FormatStyle().month(.wide).year()) }

    func hasPayments(on day: Date) -> Bool {
        paymentsByDate.contains { $0.date == Calendar.current.startOfDay(for: day) }
    }
}
