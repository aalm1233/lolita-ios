import SwiftUI

struct PaymentCalendarScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = PaymentCalendarViewModel()
    @State private var selectedDate: Date?
    @State private var mutationId: Int64?
    @State private var paymentError: String?

    private var accent: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    init(month: Date = Date()) {
        let vm = PaymentCalendarViewModel()
        vm.currentMonth = month
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                NavigationLink("月预算与年度付款", destination: FinanceOverviewScreen(month: viewModel.currentMonth))
                summaryBar
                LolitaCard(variant: .gallery) {
                    VStack(spacing: 12) {
                        monthPicker
                        calendarGrid
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
                }
                if let selectedDate {
                    dayDetail(viewModel.selectedDayPayments ?? [], date: selectedDate)
                } else {
                    Text("选择日期，查看当日付款记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .padding(16)
        }
        .background { CalendarBackground() }
        .lolitaNavBar(title: "付款日历", showBack: true)
        .toolbar { ToolbarItem(placement: .primaryAction) { CalendarBackgroundPicker() } }
        .alert("付款操作失败", isPresented: Binding(get: { paymentError != nil }, set: { if !$0 { paymentError = nil } })) {
            Button("确定") { paymentError = nil }
        } message: { Text(paymentError ?? "") }
        .onAppear { selectedDate = nil; viewModel.load() }
        .onChange(of: viewModel.currentMonth) { _, _ in selectedDate = nil }
        .onDisappear { viewModel.stopObserving() }
    }

    private var monthPicker: some View {
        HStack {
            Button { viewModel.goToPreviousMonth() } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("上个月")
            Spacer()
            Text(viewModel.monthYearText)
                .font(.headline)
            Spacer()
            Button { viewModel.goToNextMonth() } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("下个月")
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            summaryCard("全部待付", amount: viewModel.totalUnpaid, symbol: "creditcard", color: accent)
            summaryCard("全部逾期", amount: viewModel.overdueAmount, symbol: "exclamationmark.triangle", color: .red)
        }
    }

    private func summaryCard(_ title: String, amount: Double, symbol: String, color: Color) -> some View {
        LolitaCard(variant: .compact) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "¥%.2f", amount))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var calendarGrid: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: viewModel.currentMonth))!
        let daysInMonth = cal.range(of: .day, in: .month, for: start)!.count
        let firstWeekday = cal.component(.weekday, from: start)

        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(["日","一","二","三","四","五","六"], id: \.self) { day in
                Text(day).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }

            ForEach(0..<(firstWeekday - 1), id: \.self) { _ in
                Color.clear.frame(height: 44)
            }

            ForEach(1...daysInMonth, id: \.self) { day in
                let date = cal.date(byAdding: .day, value: day - 1, to: start)!
                let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
                Button {
                    selectedDate = date
                    viewModel.selectDay(date)
                } label: {
                    PaymentCalendarDayCell(day: day, hasPayments: viewModel.hasPayments(on: date), isSelected: isSelected,
                                           isToday: cal.isDateInToday(date), accent: accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(.dateTime.year().month().day()))
                .accessibilityValue(viewModel.hasPayments(on: date) ? "有付款记录" : "无付款记录")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func dayDetail(_ payments: [PaymentWithItemInfo], date: Date) -> some View {
        LolitaSection(title: date.formatted(.dateTime.month().day()) + "付款") {
            if payments.isEmpty {
                Text("当日无付款记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(payments, id: \.paymentId) { payment in
                    let overdue = payment.dueDate < Int64(Date().timeIntervalSince1970 * 1000)
                    let status = payment.isPaid ? "已付" : (overdue ? "逾期" : "待付")
                    let color: Color = payment.isPaid ? .green : (overdue ? .red : .orange)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink { ItemDetailScreen(itemId: payment.itemId) } label: { Text(payment.itemName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            }.buttonStyle(.plain)
                            LolitaBadge(text: status, color: color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "¥%.2f", payment.amount))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)
                        }
                        HStack(spacing: 16) {
                            NavigationLink { PaymentEditScreen(priceId: payment.priceId, paymentId: payment.paymentId) } label: {
                                Label(payment.isPaid ? "更正付款" : "记录真实付款", systemImage: "pencil")
                            }
                            Spacer()
                            if !payment.isPaid && payment.stageId == nil {
                                Button {
                                    mutationId = payment.paymentId
                                    Task {
                                        defer { mutationId = nil }
                                        do { try await viewModel.markPaid(payment) }
                                        catch { paymentError = userFacingError(error) }
                                    }
                                } label: {
                                    if mutationId == payment.paymentId { ProgressView() }
                                    else { Label("标记已付", systemImage: "checkmark.circle") }
                                }.disabled(mutationId != nil)
                            }
                        }.font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(accent)
                    }
                    .padding(.vertical, 4)
                    if payment.paymentId != payments.last?.paymentId { Divider() }
                }
            }
        }
    }
}

struct PaymentCalendarDayCell: View {
    @ScaledMetric(relativeTo: .subheadline) private var dayHeight: CGFloat = 44
    let day: Int
    let hasPayments: Bool
    let isSelected: Bool
    let isToday: Bool
    let accent: Color

    init(day: Int, hasPayments: Bool, isSelected: Bool, isToday: Bool, accent: Color) {
        self.day = day
        self.hasPayments = hasPayments
        self.isSelected = isSelected
        self.isToday = isToday
        self.accent = accent
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(day)")
                .font(.subheadline.weight(isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(isToday && !isSelected ? accent : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Circle()
                .fill(hasPayments ? accent : .clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: max(44, dayHeight))
        .background(isSelected ? accent.opacity(0.16) : (isToday ? accent.opacity(0.06) : .clear),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? accent : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
