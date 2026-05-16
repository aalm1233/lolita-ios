import GRDB
import Foundation

// MARK: - Enums

enum ItemStatus: String, CaseIterable, DatabaseValueConvertible {
    case owned = "OWNED"
    case wished = "WISHED"
    case pendingBalance = "PENDING_BALANCE"
}

enum ItemPriority: String, CaseIterable, DatabaseValueConvertible {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

enum CategoryGroup: String, CaseIterable, DatabaseValueConvertible {
    case clothing = "CLOTHING"
    case accessory = "ACCESSORY"
}

// MARK: - List<String> JSON converter

extension [String]: @retroactive DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "[]".databaseValue
        }
        return json.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> [String]? {
        guard let string = String.fromDatabaseValue(dbValue),
              let data = string.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
