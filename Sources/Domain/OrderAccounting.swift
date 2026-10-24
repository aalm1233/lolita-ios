import Foundation

/// Keep old Double values intact in storage; use integer cents for ledger decisions.
enum OrderAccounting {
    /// Collection prices describe the current purchase. Archived plans must not
    /// accumulate into the next purchase; pre-ledger quotes remain visible for review.
    static func displayAmounts(prices: [Price], bindings: [OrderBinding], stages: [PaymentStage], references: [ItemReferencePrice] = []) -> [Int64: Double] {
        let current = Dictionary(uniqueKeysWithValues: bindings.map { ($0.itemId, $0.priceId) })
        let planned = Set(stages.map(\.priceId))
        var values: [Int64: Double] = [:]
        for (itemId, records) in Dictionary(grouping: prices, by: \.itemId) {
            if let id = current[itemId] { values[itemId] = records.first { $0.id == id }?.totalPrice }
            else if !records.contains(where: { planned.contains($0.id) || $0.purchaseRecordStatus != .needsReview }) {
                values[itemId] = try? sum(records.map(\.totalPrice))
            }
        }
        for reference in references where current[reference.itemId] == nil { values[reference.itemId] = reference.amount }
        return values
    }

    static func cents(_ value: Double) throws -> Int64 {
        guard value.isFinite, abs(value) < 90_000_000_000_000 else {
            throw ValidationError.invalid("金额超出支持范围")
        }
        guard let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { throw ValidationError.invalid("金额超出支持范围") }
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func validate(_ value: Double, positive: Bool = false) throws {
        guard value.isFinite, positive ? value > 0 : value >= 0 else { throw ValidationError.invalid("金额无效") }
        _ = try cents(value)
        guard let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { throw ValidationError.invalid("金额超出支持范围") }
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard scaled == rounded else {
            throw ValidationError.invalid("金额最多保留两位小数")
        }
    }

    static func sum(_ values: [Double]) throws -> Double {
        var result: Int64 = 0
        for value in values {
            let (next, overflow) = result.addingReportingOverflow(try cents(value))
            guard !overflow else { throw ValidationError.invalid("合计金额超出支持范围") }
            result = next
        }
        return Double(result) / 100
    }

    static func paidByStage(_ stages: [PaymentStage], payments: [Payment]) throws -> [Int64: Double] {
        var result: [Int64: Double] = [:]
        for priceId in Set(stages.map(\.priceId)) {
            let actual = payments.filter { $0.isPaid && $0.priceId == priceId }
            var unassigned = try cents(sum(actual.filter { $0.stageId == nil }.map(\.amount)))
            for stage in stages.filter({ $0.priceId == priceId }).sorted(by: { $0.id < $1.id }) {
                let planned = max(0, try cents(stage.amount))
                let direct = min(planned, try cents(sum(actual.filter { $0.stageId == stage.id }.map(\.amount))))
                let allocated = min(planned - direct, unassigned)
                unassigned -= allocated
                result[stage.id] = Double(direct + allocated) / 100
            }
        }
        return result
    }

    static func remainingByStage(_ stages: [PaymentStage], payments: [Payment], total: Double) throws -> [Int64: Double] {
        let paid = try paidByStage(stages, payments: payments)
        var remaining = max(0, try cents(total) - cents(sum(payments.filter(\.isPaid).map(\.amount))))
        var result: [Int64: Double] = [:]
        for stage in stages.sorted(by: { $0.id < $1.id }) {
            let amount = min(remaining, max(0, try cents(stage.amount) - cents(paid[stage.id] ?? 0)))
            remaining -= amount
            result[stage.id] = Double(amount) / 100
        }
        return result
    }
}
