import GRDB
import Foundation

// MARK: - Enums

enum ItemStatus: String, CaseIterable, Codable, DatabaseValueConvertible {
    case owned = "OWNED"
    case wished = "WISHED"
    case pendingBalance = "PENDING_BALANCE"
}

enum ItemPriority: String, CaseIterable, Codable, DatabaseValueConvertible {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

enum CategoryGroup: String, CaseIterable, Codable, DatabaseValueConvertible {
    case clothing = "CLOTHING"
    case accessory = "ACCESSORY"
}

enum PriceType: String, CaseIterable, Codable, DatabaseValueConvertible {
    case full = "FULL"
    case depositBalance = "DEPOSIT_BALANCE"
}

// MARK: - List<String> JSON converter

// MARK: - StringList wrapper for JSON array storage

struct StringList: Codable, DatabaseValueConvertible, Equatable, ExpressibleByArrayLiteral {
    var values: [String]

    init(_ values: [String] = []) {
        self.values = values
    }

    init(arrayLiteral elements: String...) {
        self.values = elements
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
