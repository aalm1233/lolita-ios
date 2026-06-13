import SwiftUI

struct PaymentCalendarScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = PaymentCalendarViewModel()

    var body: some View {
        VStack(spacing: 0) {
            monthPicker
            summaryBar
            calendarGrid
            if let selected = viewModel.selectedDayPayments {
                dayDetail(selected)
            }
            Spacer()
        }
        .lolitaNavBar(title: "付款日历", showBack: true)
        .onAppear { viewModel.load() }
    }

    private var monthPicker: some View {
        HStack {
            Button { viewModel.goToPreviousMonth() } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(viewModel.monthYearText)
                .font(.headline)
            Spacer()
            Button { viewModel.goToNextMonth() } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            Label {
                Text("待付 ¥\(String(format: "%.2f", viewModel.totalUnpaid))")
                    .font(.caption)
            } icon: {
                Image(systemName: "creditcard")
            }

            Label {
                Text("逾期 ¥\(String(format: "%.2f", viewModel.overdueAmount))")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .padding()
        .background(skinManager.current.backgroundColor.opacity(0.5))
    }

    private var calendarGrid: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: viewModel.currentMonth))!
        let daysInMonth = cal.range(of: .day, in: .month, for: start)!.count
        let firstWeekday = cal.component(.weekday, from: start)

        let columns = Array(repeating: GridItem(.flexible()), count: 7)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(["日","一","二","三","四","五","六"], id: \.self) { day in
                Text(day).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }

            ForEach(0..<(firstWeekday - 1), id: \.self) { _ in Color.clear }

            ForEach(1...daysInMonth, id: \.self) { day in
                let date = cal.date(byAdding: .day, value: day - 1, to: start)!
                Button {
                    viewModel.selectDay(date)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(day)")
                            .font(.caption)
                        Circle()
                            .fill(viewModel.hasPayments(on: date) ? skinManager.current.primaryColor : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func dayDetail(_ payments: [PaymentWithItemInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当日付款")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)

            ForEach(payments, id: \.paymentId) { p in
                HStack {
                    Circle()
                        .fill(p.isPaid ? Color.green : (p.dueDate < Int64(Date().timeIntervalSince1970 * 1000) ? Color.red : Color.orange))
                        .frame(width: 8, height: 8)
                    Text(p.itemName)
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "¥%.2f", p.amount))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}
