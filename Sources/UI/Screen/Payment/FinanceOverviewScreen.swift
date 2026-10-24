import SwiftUI

struct FinanceOverviewScreen: View {
    @AppStorage("showTotalPrice") private var showAmount = true
    @State private var snapshot = FinanceSnapshot()
    @State private var month: Date
    @State private var annual = false
    @State private var error: String?
    @State private var removing: MonthlyBudget?
    init(month: Date = Date(), annual: Bool = false) { _month = State(initialValue: month); _annual = State(initialValue: annual) }
    private var summary: FinanceMonth { snapshot.month(month) }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("查看范围", selection: $annual) { Text("月预算").tag(false); Text("年度付款").tag(true) }.pickerStyle(.segmented)
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel(annual ? "上一年" : "上个月")
                    Spacer(); Text(annual ? String(Calendar.current.component(.year, from: month)) + "年" : FinanceSnapshot.monthKey(month)).font(.headline); Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel(annual ? "下一年" : "下个月")
                }
                if annual { yearContent } else { monthContent }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding(16).padding(.bottom, 80)
        }
        .lolitaNavBar(title: "预算与资金", showBack: true)
        .task { for await value in AppModule.shared.financeRepository.observe() { guard !Task.isCancelled else { return }; snapshot = value } }
        .confirmationDialog("移除本月预算？原付款和退款保留。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("移除预算", role: .destructive) {
                guard let budget = removing else { return }; removing = nil
                Task { do { try await AppModule.shared.financeRepository.deleteBudget(budget) } catch { self.error = userFacingError(error) } }
            }
        }
    }
    private var monthContent: some View {
        Group {
            LolitaSection(title: "本月预算") {
                FinanceValueRow(title: "预算", amount: summary.budget.map { Double($0.amountCents) / 100 })
                FinanceValueRow(title: "本月原实付", amount: summary.paid)
                FinanceValueRow(title: "本月到账退款", amount: summary.refunded)
                FinanceValueRow(title: "本月净支出", amount: summary.net)
                FinanceValueRow(title: "本月待付", amount: summary.pending)
                FinanceValueRow(title: "以前月份未付", amount: summary.earlierPending)
                FinanceValueRow(title: "预计可用", amount: summary.projectedRemaining)
                NavigationLink("设置月预算", destination: FinanceEditorScreen(mode: .budget(FinanceSnapshot.monthKey(month))))
                if let budget = summary.budget { Button("移除本月预算", role: .destructive) { removing = budget } }
            }
            LolitaSection(title: "日期待核对") {
                FinanceValueRow(title: "未定日期的待付", amount: summary.undatedPending)
                FinanceValueRow(title: "未知日期的原实付", amount: summary.undatedPaid)
                Text("未知日期不推测月份，也不计入本月预算。退款按实际到账月扣减，净支出可能为负。").font(.caption).foregroundStyle(.secondary)
            }
            entries(summary.entries, title: "本月流水与以前未付")
            if !summary.undated.isEmpty { entries(summary.undated, title: "未知日期明细") }
        }
    }
    private var yearContent: some View {
        VStack(spacing: 16) {
            Text("已付与退款使用真实发生日期，待付按当前订单的阶段余款列入。未知日期不分配到月份。").font(.caption).foregroundStyle(.secondary)
            ForEach(1...12, id: \.self) { number in
                let date = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: month), month: number, day: 1))!
                let value = snapshot.month(date)
                LolitaSection(title: "\(number)月") {
                    FinanceValueRow(title: "原实付", amount: value.paid)
                    FinanceValueRow(title: "到账退款", amount: value.refunded)
                    FinanceValueRow(title: "净支出", amount: value.net)
                    FinanceValueRow(title: "待付", amount: value.pending)
                    NavigationLink("查看\(number)月预算与明细", destination: FinanceOverviewScreen(month: date))
                }
            }
        }
    }
    private func entries(_ rows: [FinanceEntry], title: String) -> some View {
        LolitaSection(title: title) {
            if rows.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
            ForEach(rows) { entry in
                NavigationLink(destination: PaymentManageScreen(priceId: entry.priceId)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.itemName).foregroundStyle(.primary)
                        Text((entry.isRefund ? "到账退款 " : entry.isPaid ? "原实付 " : "待付 ") + (showAmount ? detailMoney(abs(entry.amount)) : "金额已隐藏"))
                        Text(entry.date.map(detailDate) ?? "日期未知").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
        }
    }
    private func move(_ offset: Int) { month = Calendar.current.date(byAdding: annual ? .year : .month, value: offset, to: month) ?? month }
}
