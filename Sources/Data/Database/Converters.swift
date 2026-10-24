import GRDB
import Foundation

// MARK: - Enums

enum ItemStatus: String, CaseIterable, Codable, Sendable, DatabaseValueConvertible {
    case owned = "OWNED"
    case wished = "WISHED"
    case pendingBalance = "PENDING_BALANCE"
    case pendingPayment = "PENDING_PAYMENT"
    case pendingReview = "PENDING_REVIEW"

    var displayName: String {
        switch self {
        case .owned: "已拥有"
        case .wished: "心愿"
        case .pendingBalance: "待尾款"
        case .pendingPayment: "待付款"
        case .pendingReview: "待核对"
        }
    }
}

enum ItemPriority: String, CaseIterable, Codable, Sendable, DatabaseValueConvertible {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

enum CategoryGroup: String, CaseIterable, Codable, Sendable, DatabaseValueConvertible {
    case clothing = "CLOTHING"
    case accessory = "ACCESSORY"
}

enum PriceType: String, CaseIterable, Codable, Sendable, DatabaseValueConvertible {
    case full = "FULL"
    case depositBalance = "DEPOSIT_BALANCE"
    case multiStage = "MULTI_STAGE"

    var displayName: String {
        switch self { case .full: "全款"; case .depositBalance: "定金与尾款"; case .multiStage: "多阶段" }
    }
}

enum PurchaseRecordStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case tracked = "TRACKED"
    case historicalOwned = "HISTORICAL_OWNED"
    case needsReview = "NEEDS_REVIEW"
}

// MARK: - List<String> JSON converter

// MARK: - StringList wrapper for JSON array storage

struct StringList: Codable, Sendable, DatabaseValueConvertible, Equatable, ExpressibleByArrayLiteral {
    var values: [String]

    init(_ values: [String] = []) {
        self.values = values
    }

    init(arrayLiteral elements: String...) {
        self.values = elements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let values = try? container.decode([String].self) { self.values = values }
        else {
            // Accept backups from the initial iOS version as well as Android arrays.
            let legacy = try container.decode([String: [String]].self)
            guard let values = legacy["values"] else { throw ValidationError.invalid("图片/颜色列表格式无效") }
            self.values = values
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    var databaseValue: DatabaseValue {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return "[]".databaseValue
        }
        return json.databaseValue
    }

    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> StringList? {
        guard let string = String.fromDatabaseValue(dbValue),
              let data = string.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return StringList(values)
    }
}

// Validation belongs at the data boundary so every entry point follows the same rules.
enum ValidationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum InputValidation {
    static func name(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ValidationError.invalid("名称不能为空") }
        return value
    }

    static func amount(_ text: String, label: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value >= 0 else {
            throw ValidationError.invalid("\(label)请输入有效的非负金额")
        }
        return value
    }
}

struct PaymentMonthRange {
    let start: Int64
    let end: Int64

    init(month: Date, calendar: Calendar = .current) {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let next = calendar.date(byAdding: .month, value: 1, to: first)!
        start = Int64(first.timeIntervalSince1970 * 1000)
        end = Int64(next.timeIntervalSince1970 * 1000)
    }
}

func userFacingError(_ error: Error) -> String {
    guard let databaseError = error as? DatabaseError else { return error.localizedDescription }
    switch databaseError.extendedResultCode {
    case .SQLITE_CONSTRAINT_UNIQUE: return "名称已存在，请换一个名称。"
    case .SQLITE_CONSTRAINT_FOREIGNKEY: return "关联记录不存在或仍被使用，请先核对关联。"
    default: return "数据操作失败，请稍后重试。"
    }
}
