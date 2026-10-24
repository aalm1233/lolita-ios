import Foundation
@preconcurrency import GRDB

enum TaobaoPaymentRole: String, CaseIterable, Identifiable, Sendable {
    case full = "全款", deposit = "定金", balance = "尾款"
    var id: String { rawValue }
}

struct TaobaoImportDraft: Identifiable, Sendable {
    var id: String { original.id }
    let original: TaobaoOrderItem
    var name: String
    var brandId: Int64 = 0
    var categoryId: Int64 = 0
    var color = ""
    var size = ""
    var priceText: String
    var purchaseDate: String
    var imagePath: String?
    var role: TaobaoPaymentRole = .full
    var pairedWith: String?
    var manualBalanceText = ""
    var balanceDueDate = Date()
    var included = true

    init(original: TaobaoOrderItem) {
        self.original = original
        name = TaobaoImportMatching.cleanName(original.name)
        if name.isEmpty { name = original.name }
        color = original.parsedColor ?? ""
        size = original.parsedSize ?? ""
        priceText = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), original.price)
        purchaseDate = original.orderTime.isEmpty ? Date().formatted(.iso8601.year().month().day()) : original.orderTime
        role = TaobaoImportMatching.detectRole(original.name)
    }
}

enum TaobaoMissingKind: String, Sendable { case brand = "品牌", category = "分类" }
struct TaobaoMissingAttribute: Identifiable, Sendable {
    var id: String { kind.rawValue + ":" + name }
    let name: String
    let kind: TaobaoMissingKind
    let group: CategoryGroup
    var included = true
}

struct TaobaoImportAttributes: Sendable {
    var brands: [Brand]
    var categories: [Category]
    var importedKeys: Set<String>
}

struct TaobaoImportResult: Sendable {
    var importedCount = 0
    var mergedCount = 0
    var duplicateCount = 0
    var omittedCount = 0
}

final class TaobaoImportRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func attributes() async throws -> TaobaoImportAttributes {
        try await db.read { @Sendable db in
            TaobaoImportAttributes(brands: try Brand.order(Brand.Columns.name).fetchAll(db), categories: try Category.order(Category.Columns.name).fetchAll(db), importedKeys: Set(try Item.fetchAll(db).flatMap { $0.importOrderKeys?.values ?? [] }))
        }
    }

    func prepareAttributes(_ missing: [TaobaoMissingAttribute]) async throws -> TaobaoImportAttributes {
        try await db.write { @Sendable db in
            for attribute in missing where attribute.included {
                let name = try InputValidation.name(attribute.name)
                switch attribute.kind {
                case .brand:
                    if try Brand.filter(sql: "LOWER(name) = LOWER(?)", arguments: [name]).fetchOne(db) == nil {
                        var brand = Brand(name: name); try brand.insert(db)
                    }
                case .category:
                    if try Category.filter(sql: "LOWER(name) = LOWER(?)", arguments: [name]).fetchOne(db) == nil {
                        var category = Category(name: name, group: attribute.group); try category.insert(db)
                    }
                }
            }
            return TaobaoImportAttributes(brands: try Brand.order(Brand.Columns.name).fetchAll(db), categories: try Category.order(Category.Columns.name).fetchAll(db), importedKeys: Set(try Item.fetchAll(db).flatMap { $0.importOrderKeys?.values ?? [] }))
        }
    }

    /// Validate and commit the complete submitted snapshot in one transaction.
    /// Import identifiers are checked again inside the write, so retrying cannot duplicate records.
    func save(_ drafts: [TaobaoImportDraft]) async throws -> TaobaoImportResult {
        try await db.write { @Sendable db in
            let selected = drafts.filter(\.included)
            guard !selected.isEmpty else { throw ValidationError.invalid("请至少选择一件商品") }
            guard Set(drafts.map(\.id)).count == drafts.count else { throw ValidationError.invalid("导入列表包含重复订单商品") }
            let byID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
            var importedKeys = Set(try Item.fetchAll(db).flatMap { $0.importOrderKeys?.values ?? [] })
            var processed = Set<String>()
            var result = TaobaoImportResult(omittedCount: drafts.count - selected.count)
            for draft in selected where !processed.contains(draft.id) {
                let partner = draft.pairedWith.flatMap { byID[$0] }
                if draft.pairedWith != nil {
                    guard let partner, partner.pairedWith == draft.id, partner.role != draft.role,
                          draft.role != .full, partner.role != .full else {
                        throw ValidationError.invalid("“\(draft.name)”的定金尾款配对不完整，请解除或重新配对")
                    }
                }
                let keys = [draft.id] + (partner.map { [$0.id] } ?? [])
                if keys.contains(where: { importedKeys.contains($0) }) {
                    // A partial historical pair cannot be merged without changing a previously saved item.
                    guard keys.allSatisfy({ importedKeys.contains($0) }) else {
                        throw ValidationError.invalid("“\(draft.name)”的部分订单已导入，请解除配对并核对现有付款记录")
                    }
                    processed.formUnion(keys); result.duplicateCount += keys.count; continue
                }
                let main: TaobaoImportDraft
                let depositDraft: TaobaoImportDraft?
                let balanceDraft: TaobaoImportDraft?
                if let partner {
                    depositDraft = draft.role == .deposit ? draft : partner
                    balanceDraft = draft.role == .balance ? draft : partner
                    main = depositDraft!
                } else { main = draft; depositDraft = draft.role == .deposit ? draft : nil; balanceDraft = nil }
                guard try Brand.fetchOne(db, key: main.brandId) != nil, try Category.fetchOne(db, key: main.categoryId) != nil else {
                    throw ValidationError.invalid("请为“\(main.name)”选择品牌和分类")
                }
                let name = try InputValidation.name(main.name)
                let amount = try InputValidation.amount(main.priceText, label: "\(name)金额")
                let purchaseDate = try TaobaoImportMatching.date(main.purchaseDate)
                var item = Item(name: name, brandId: main.brandId, categoryId: main.categoryId,
                                description: "淘宝订单：\(keys.joined(separator: "、"))\n型号款式：\(main.original.styleSpec)",
                                colors: StringList(main.color.isEmpty ? [] : [main.color]), size: main.size.isEmpty ? nil : main.size,
                                imageUrls: StringList([main.imagePath ?? balanceDraft?.imagePath].compactMap { $0 }), source: "淘宝")
                item.importOrderKeys = StringList(keys)
                try item.insert(db)
                var price: Price
                let due: Int64?
                if depositDraft != nil {
                    let balance: Double
                    if let balanceDraft {
                        balance = try InputValidation.amount(balanceDraft.priceText, label: "\(name)尾款")
                        guard balance > 0 else { throw ValidationError.invalid("“\(name)”的尾款必须大于 0") }
                        due = try TaobaoImportMatching.date(balanceDraft.purchaseDate)
                    } else {
                        balance = try InputValidation.amount(main.manualBalanceText, label: "\(name)待付尾款")
                        guard balance > 0 else { throw ValidationError.invalid("请为“\(name)”填写大于 0 的待付尾款") }
                        guard main.balanceDueDate.timeIntervalSince1970.isFinite else { throw ValidationError.invalid("尾款截止日期无效") }
                        due = Int64(main.balanceDueDate.timeIntervalSince1970 * 1000)
                    }
                    guard (amount + balance).isFinite else { throw ValidationError.invalid("“\(name)”的总金额过大") }
                    price = Price(itemId: item.id, type: .depositBalance, totalPrice: amount + balance, deposit: amount, balance: balance)
                } else { price = Price(itemId: item.id, type: .full, totalPrice: amount); due = nil }
                try price.insert(db)
                var paid = Payment(priceId: price.id, amount: amount, dueDate: purchaseDate, isPaid: true, paidDate: purchaseDate)
                try paid.insert(db)
                if let due {
                    var balancePayment = Payment(priceId: price.id, amount: price.balance ?? 0, dueDate: due, isPaid: balanceDraft != nil, paidDate: balanceDraft != nil ? due : nil)
                    try balancePayment.insert(db)
                }
                // Import into the same ledger in this transaction. Unpaid legacy rows are
                // retained as source records; the active schedule is projected from stages.
                let records = try Payment.filter(Payment.Columns.priceId == price.id).order(Payment.Columns.id).fetchAll(db)
                for record in records {
                    var stage = PaymentStage(priceId: price.id, name: price.type == .full ? "全款" : record.id == paid.id ? "定金" : "尾款",
                                             amount: record.amount, dueDate: record.dueDate)
                    try stage.insert(db)
                    try db.execute(sql: "UPDATE payments SET stageId = ? WHERE id = ?", arguments: [stage.id, record.id])
                }
                price.purchaseRecordStatus = .tracked; try price.update(db)
                try OrderBinding(itemId: item.id, priceId: price.id).insert(db)
                try OrderRepository.refreshStatuses(db, itemId: item.id)
                importedKeys.formUnion(keys); processed.formUnion(keys)
                result.importedCount += 1
                if partner != nil { result.mergedCount += 1 }
            }
            return result
        }
    }
}

enum TaobaoImportMatching {
    static func date(_ value: String) throws -> Int64 {
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            formatter.isLenient = false
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = formatter.date(from: text), formatter.string(from: date) == text {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
        }
        throw ValidationError.invalid("购买日期“\(value)”无效，请使用 yyyy-MM-dd 或 yyyy-MM-dd HH:mm 格式")
    }

    static func detectRole(_ name: String) -> TaobaoPaymentRole {
        let deposit = name.range(of: "定-?金", options: .regularExpression)
        let balance = name.range(of: "尾款")
        if let deposit, let balance { return deposit.lowerBound < balance.lowerBound ? .deposit : .balance }
        if deposit != nil { return .deposit }
        if balance != nil { return .balance }
        return .full
    }

    static func cleanName(_ name: String) -> String {
        var cleaned = name
        for pattern in ["【[^】]*】", "＜[^＞]*＞", "[（(](?:定-?金|尾款)[）)]", "CP先行|定-?金|尾款", "^\\s*-\\s*"] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func brand(_ shop: String, in brands: [Brand]) -> Brand? {
        guard !shop.isEmpty else { return nil }
        if let exact = brands.first(where: { $0.name.caseInsensitiveCompare(shop) == .orderedSame }) { return exact }
        return brands.filter { !$0.name.isEmpty && (shop.localizedCaseInsensitiveContains($0.name) || $0.name.localizedCaseInsensitiveContains(shop)) }.max { $0.name.count < $1.name.count }
    }

    static func category(_ type: String?, in categories: [Category]) -> Category? {
        guard let type, !type.isEmpty else { return nil }
        if let exact = categories.first(where: { $0.name.caseInsensitiveCompare(type) == .orderedSame }) { return exact }
        let mappings: [(String, [String])] = [
            ("OP", ["OP", "开襟OP", "堆褶OP", "堆褶开襟OP", "连衣裙"]), ("JSK", ["JSK"]),
            ("SK", ["SK", "拼色SK", "半裙", "格裙", "长裙", "罩裙"]), ("衬衫", ["衬衫"]),
            ("斗篷", ["斗篷", "罩衫斗篷", "罩衫"]), ("外套", ["外套", "长外套", "大衣"]),
            ("帽子", ["帽子", "贝雷帽"]), ("其他头饰", ["头饰", "蝴蝶结头饰", "KC", "发箍", "发带", "发夹", "边夹", "头纱"]),
            ("腰封", ["腰封", "拖尾腰封", "印花钢骨腰封"]), ("手袖", ["手袖", "接袖", "袖子"]),
            ("包", ["包", "包包"]), ("短裤", ["短裤", "南瓜裤"]), ("项链", ["项链", "吊坠"]),
            ("上衣", ["上衣", "胸衣", "蝙蝠胸衣"])
        ]
        for (name, aliases) in mappings where aliases.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) {
            if let category = categories.first(where: { $0.name == name }) { return category }
        }
        return nil
    }

    static func group(_ type: String) -> CategoryGroup {
        ["头饰", "蝴蝶结", "帽子", "KC", "发带", "发夹", "包", "鞋", "袜", "手套", "项链", "耳环", "戒指", "胸针", "腰链"].contains(where: { type.localizedCaseInsensitiveContains($0) }) ? .accessory : .clothing
    }

    static func autoPair(_ drafts: [TaobaoImportDraft]) -> [TaobaoImportDraft] {
        var result = drafts
        var used = Set(drafts.indices.filter { drafts[$0].pairedWith != nil })
        for depositIndex in drafts.indices where drafts[depositIndex].role == .deposit && drafts[depositIndex].pairedWith == nil {
            let deposit = drafts[depositIndex]
            let core = coreName(deposit.original.name)
            let candidates = drafts.indices.filter { index in
                let balance = drafts[index]
                guard !used.contains(index), balance.role == .balance, balance.pairedWith == nil else { return false }
                if !deposit.size.isEmpty, !balance.size.isEmpty, deposit.size.caseInsensitiveCompare(balance.size) != .orderedSame { return false }
                if !deposit.color.isEmpty, !balance.color.isEmpty, deposit.color.caseInsensitiveCompare(balance.color) != .orderedSame { return false }
                let sameURL = !deposit.original.productURL.isEmpty && deposit.original.productURL == balance.original.productURL
                let balanceCore = coreName(balance.original.name)
                let sameName = !core.isEmpty && core == balanceCore
                let sameShop = !deposit.original.shopName.isEmpty && deposit.original.shopName == balance.original.shopName
                return sameURL || (sameName && sameShop)
            }
            // An ambiguous match stays unpaired for manual review.
            if candidates.count == 1, let balanceIndex = candidates.first {
                result[depositIndex].pairedWith = drafts[balanceIndex].id
                result[balanceIndex].pairedWith = deposit.id
                used.insert(balanceIndex)
            }
        }
        return result
    }

    private static func coreName(_ name: String) -> String {
        cleanName(name).replacingOccurrences(of: "[（(][^）)]*[）)]|需要?有.*|需补.*|[\\s*·-]", with: "", options: .regularExpression).lowercased()
    }
}
