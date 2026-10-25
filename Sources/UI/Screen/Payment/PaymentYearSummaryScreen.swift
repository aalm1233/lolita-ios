import SwiftUI

/// Uses the repository's effective dates: actual paid date for receipts, due date for remaining stages.
struct PaymentYearSnapshot {
    let payments: [PaymentWithItemInfo]
    let calendar: Calendar
    let now: Int64

    func month(_ month: Int) -> [PaymentWithItemInfo] {
        payments.filter { calendar.component(.month, from: Date(timeIntervalSince1970: Double($0.dueDate) / 1000)) == month }
    }
    func paid(_ rows: [PaymentWithItemInfo]) -> Double { total(rows.filter(\.isPaid)) }
    func pending(_ rows: [PaymentWithItemInfo]) -> Double { total(rows.filter { !$0.isPaid }) }
    func overdue(_ rows: [PaymentWithItemInfo]) -> Double { total(rows.filter { !$0.isPaid && $0.dueDate < now }) }
    private func total(_ rows: [PaymentWithItemInfo]) -> Double { (try? OrderAccounting.sum(rows.map(\.amount))) ?? 0 }

    static func range(year: Int, calendar: Calendar) -> Range<Int64> {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(byAdding: .year, value: 1, to: start)!
        return Int64(start.timeIntervalSince1970 * 1000)..<Int64(end.timeIntervalSince1970 * 1000)
    }
    static func compact(_ amount: Double) -> String {
        amount >= 10_000 ? String(format: "%.1f万", amount / 10_000) : String(format: "%.0f", amount)
    }
}

@MainActor
final class PaymentYearViewModel: ObservableObject {
    @Published private(set) var year: Int
    @Published private(set) var selectedMonth: Int?
    @Published private(set) var payments: [PaymentWithItemInfo] = []
    @Published private(set) var calendar: Calendar
    @Published private(set) var now: Int64
    private let repository: PaymentRepository
    private var generation = UUID()

    init(repository: PaymentRepository = AppModule.shared.paymentRepository, calendar: Calendar = .current, date: Date = Date()) {
        self.repository = repository; self.calendar = calendar
        year = calendar.component(.year, from: date)
        now = Int64(date.timeIntervalSince1970 * 1000)
    }
    var observationKey: String { "\(year):\(calendar.timeZone.identifier)" }
    var snapshot: PaymentYearSnapshot { PaymentYearSnapshot(payments: payments, calendar: calendar, now: now) }
    func changeYear(_ delta: Int) { year += delta; selectedMonth = nil; payments = []; generation = UUID() }
    func selectMonth(_ month: Int) { selectedMonth = selectedMonth == month ? nil : month }
    func refreshTime(date: Date = Date(), calendar: Calendar = .current) {
        now = Int64(date.timeIntervalSince1970 * 1000)
        if self.calendar.timeZone != calendar.timeZone { self.calendar = calendar; payments = []; generation = UUID() }
    }
    /// Owned by SwiftUI .task(id:); leaving the page or changing year/zone cancels both tasks.
    func observe() async {
        let token = UUID(); generation = token
        let range = PaymentYearSnapshot.range(year: year, calendar: calendar)
        let clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let next = self.payments.filter { !$0.isPaid && $0.dueDate >= self.now }.map(\.dueDate).min()
                let delay = min(60_000, max(1, (next.map { $0 - self.now + 1 }) ?? 60_000))
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                self.refreshTime()
            }
        }
        defer { clock.cancel() }
        for await values in repository.getByDateRange(start: range.lowerBound, end: range.upperBound) {
            guard !Task.isCancelled, generation == token else { return }
            payments = values
        }
    }
}

struct PaymentYearSummaryScreen: View {
    @StateObject private var model = PaymentYearViewModel()
    @AppStorage("showTotalPrice") private var showMoney = true
    @Environment(\.scenePhase) private var scenePhase
    var onBackgroundOptions: () -> Void = {}

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(spacing: 6) {
                PaymentCalendarSurface(radius: 20) {
                    VStack(spacing: 4) {
                        HStack {
                            Button { model.changeYear(-1) } label: { SkinIcon(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一年")
                            Spacer(minLength: 0)
                            Text("\(String(model.year))年").font(.subheadline.weight(.semibold)).accessibilityIdentifier("payment-year")
                            Spacer(minLength: 0)
                            Button { model.changeYear(1) } label: { SkinIcon(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下一年")
                        }
                        if showMoney {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { annualTotals(snapshot) }
                                VStack(spacing: 4) { annualTotals(snapshot) }
                            }
                            .font(.caption).monospacedDigit()
                            if snapshot.overdue(snapshot.payments) > 0 {
                                Text("⚠ 逾期 \(money(snapshot.overdue(snapshot.payments)))")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.red)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 8)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(1...12, id: \.self) { month in
                        let rows = snapshot.month(month)
                        Button { model.selectMonth(month) } label: {
                            PaymentYearMonthCard(month: month, paid: snapshot.paid(rows), pending: snapshot.pending(rows), overdue: snapshot.overdue(rows), selected: model.selectedMonth == month, showMoney: showMoney)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("payment-month-\(month)")
                        .accessibilityLabel(monthLabel(month, rows: rows, snapshot: snapshot))
                        .accessibilityAddTraits(model.selectedMonth == month ? .isSelected : [])
                    }
                }
                Text("按实际付款日期统计已付，按应付日期统计待付。")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                NavigationLink("查看日期待定金额与预算", destination: FinanceOverviewScreen(month: monthDate, annual: false))
                    .font(.subheadline).frame(minHeight: 44)
                if !showMoney {
                    Text("金额已隐藏；记付款时将显示金额。")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let month = model.selectedMonth {
                    Text("\(month)月 付款记录").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    if snapshot.month(month).isEmpty {
                        PaymentCalendarSurface { Text("当月无付款记录").font(.subheadline).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading) }
                    } else {
                        ForEach(snapshot.month(month), id: \.paymentId) { payment in
                            PaymentYearRecordCard(payment: payment, now: model.now, calendar: model.calendar, showMoney: showMoney)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { CalendarBackground(overlayOpacity: 0.18) }
        .simultaneousGesture(LongPressGesture(minimumDuration: 5).onEnded { _ in onBackgroundOptions() })
        .task(id: model.observationKey) { await model.observe() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshTime() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.refreshTime() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in model.refreshTime() }
    }
    @ViewBuilder private func annualTotals(_ snapshot: PaymentYearSnapshot) -> some View {
        Text("本年已付 \(money(snapshot.paid(snapshot.payments)))").foregroundStyle(.green)
        Text("本年有日期待付 \(money(snapshot.pending(snapshot.payments)))").foregroundStyle(Color.accentColor)
    }
    private var monthDate: Date { model.calendar.date(from: DateComponents(year: model.year, month: model.selectedMonth ?? 1, day: 1))! }
    private func money(_ amount: Double) -> String { StatsDisplay.money(amount, visible: true) }
    private func monthLabel(_ month: Int, rows: [PaymentWithItemInfo], snapshot: PaymentYearSnapshot) -> String {
        guard showMoney else { return "\(month)月，\(rows.count)笔付款，金额已隐藏" }
        return "\(month)月，已付\(money(snapshot.paid(rows)))，待付\(money(snapshot.pending(rows)))，逾期\(money(snapshot.overdue(rows)))"
    }
}

struct PaymentYearMonthCard: View {
    @ScaledMetric(relativeTo: .caption) private var scale = 1.0
    let month: Int
    let paid: Double
    let pending: Double
    let overdue: Double
    let selected: Bool
    let showMoney: Bool
    var body: some View {
        PaymentCalendarSurface(radius: 12, selected: selected) {
            VStack(spacing: 0) {
                Text("\(month)月").font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(paid > 0 || pending > 0 ? .primary : .secondary)
                if showMoney {
                    if paid > 0 { Text("已 ¥\(PaymentYearSnapshot.compact(paid))").font(.system(size: 8 * scale)).foregroundStyle(.green) }
                    if pending > 0 { Text("待 ¥\(PaymentYearSnapshot.compact(pending))").font(.system(size: 8 * scale)).foregroundStyle(overdue > 0 ? Color.red : .accentColor) }
                    if overdue > 0 { Text("逾期").font(.system(size: 7 * scale, weight: .semibold)).foregroundStyle(.red) }
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity).frame(height: 48 * max(scale, 1))
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct PaymentYearRecordCard: View {
    let payment: PaymentWithItemInfo
    let now: Int64
    let calendar: Calendar
    let showMoney: Bool
    private var overdue: Bool { !payment.isPaid && payment.dueDate < now }
    private var status: String { payment.isPaid ? "已付款" : overdue ? "已逾期" : "待付款" }
    private var type: String { switch payment.priceType { case "FULL": "全款"; case "DEPOSIT_BALANCE": "定金尾款"; case "MULTI_STAGE": "多段付款"; default: "付款" } }
    var body: some View {
        PaymentCalendarSurface {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack { Text(payment.itemName).font(.subheadline.weight(.semibold)).lineLimit(1); Spacer(minLength: 4); badge }
                    VStack(alignment: .leading) { Text(payment.itemName).font(.subheadline.weight(.semibold)); badge }
                }
                Text(type + (showMoney ? " \(StatsDisplay.money(payment.amount, visible: true))" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(payment.isPaid ? "实付" : "应付"): \(dateText)")
                    .font(.caption).foregroundStyle(.secondary)
                if !payment.isPaid && payment.paymentId < 0 {
                    NavigationLink(destination: PaymentEditScreen(priceId: payment.priceId, paymentId: payment.paymentId)) {
                        Text("记付款").font(.subheadline).frame(minHeight: 44)
                    }.accessibilityIdentifier("record-payment-\(payment.stageId ?? -payment.paymentId)")
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var dateText: String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(payment.dueDate) / 1000))
    }
    private var badge: some View {
        Text(status).font(.caption2).foregroundStyle(payment.isPaid ? Color.green : overdue ? .red : .accentColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((payment.isPaid ? Color.green : overdue ? .red : .accentColor).opacity(0.1), in: Capsule())
    }
}

private struct PaymentCalendarSurface<Content: View>: View {
    @AppStorage("paymentCalendarBackgroundPath") private var background = ""
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 16
    var selected = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .background {
                let shape = RoundedRectangle(cornerRadius: radius)
                if !background.isEmpty && !reduceTransparency { shape.fill(.ultraThinMaterial) }
                else { shape.fill(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor) }
            }
            .overlay { RoundedRectangle(cornerRadius: radius).fill(Color.accentColor.opacity(selected ? 0.15 : 0)).allowsHitTesting(false) }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .animation(.easeInOut(duration: 0.2), value: selected)
    }
}
