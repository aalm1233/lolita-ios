import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct TaobaoOrder: Identifiable, Codable, Equatable, Sendable {
    var id: String { orderId }
    let orderId: String
    let orderTime: String
    let orderStatus: String
    let shopName: String
    let totalPaid: Double
    let shipping: Double
    var items: [TaobaoOrderItem]
    var rawPaid: String? = nil
    var rawShipping: String? = nil
}

struct TaobaoOrderItem: Identifiable, Codable, Equatable, Sendable {
    var id: String { sourceKey ?? "\(orderId):\(lineIndex)" }
    let orderId: String
    let lineIndex: Int
    let orderTime: String
    let shopName: String
    let name: String
    let productURL: String
    let styleSpec: String
    let quantity: Int
    let price: Double
    let parsedType: String?
    let parsedSize: String?
    let parsedColor: String?
    var sourceKey: String? = nil
    var unitOrdinal = 0
    var rawPrice: String? = nil
    var importMarker: String { "淘宝订单：\(orderId) / 商品 \(lineIndex + 1)" }
}

struct TaobaoParseResult: Sendable {
    let orders: [TaobaoOrder]
    let fileCount: Int
    let duplicateCount: Int
}

enum TaobaoOrderParser {
    static let maximumFileSize = 32 * 1024 * 1024

    static func parseMultipleFiles(_ files: [Data]) throws -> TaobaoParseResult {
        guard !files.isEmpty, files.count <= 50 else { throw ValidationError.invalid("请选择 1 至 50 个订单 Excel 文件") }
        var seen = Set<String>()
        var orders: [TaobaoOrder] = []
        var duplicates = 0
        for file in files {
            for order in try parse(file) {
                if seen.insert(order.orderId).inserted { orders.append(order) }
                else { duplicates += 1 }
            }
        }
        guard !orders.isEmpty else { throw ValidationError.invalid("文件中没有可导入的商品，请选择淘宝订单导出的 .xlsx 文件") }
        return TaobaoParseResult(orders: orders, fileCount: files.count, duplicateCount: duplicates)
    }

    static func parse(_ data: Data) throws -> [TaobaoOrder] {
        guard data.count <= maximumFileSize else { throw ValidationError.invalid("订单文件超过 32 MB，请分批导入") }
        let entries = try ZipArchiveReader.read(data, maximumExpandedSize: 64 * 1024 * 1024)
        var sharedStrings: [String] = []
        if let data = entries["xl/sharedStrings.xml"] {
            let delegate = SharedStringsDelegate()
            try parseXML(data, delegate: delegate)
            sharedStrings = delegate.strings
        }
        // Respect the workbook's first worksheet, including exports whose sheet is not sheet1.xml.
        let workbook = WorkbookDelegate()
        guard let workbookData = entries["xl/workbook.xml"], let relationshipsData = entries["xl/_rels/workbook.xml.rels"] else {
            throw ValidationError.invalid("Excel 工作簿结构无效")
        }
        try parseXML(workbookData, delegate: workbook)
        let relationships = RelationshipsDelegate()
        try parseXML(relationshipsData, delegate: relationships)
        guard let relationshipID = workbook.firstSheetRelationshipID,
              let target = relationships.targets[relationshipID] else { throw ValidationError.invalid("Excel 中没有工作表") }
        let sheetPath = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
        guard !sheetPath.split(separator: "/").contains(".."), sheetPath.hasPrefix("xl/"), let sheet = entries[sheetPath] else {
            throw ValidationError.invalid("Excel 工作表路径无效")
        }
        let delegate = WorksheetDelegate(sharedStrings: sharedStrings, date1904: workbook.date1904)
        try parseXML(sheet, delegate: delegate)
        if let error = delegate.failure { throw error }
        return try orders(from: delegate.rows)
    }

    static func orders(from rows: [[String]]) throws -> [TaobaoOrder] {
        guard let headerIndex = rows.firstIndex(where: { $0.contains(where: { !$0.isEmpty }) }) else { return [] }
        let header = rows[headerIndex]
        guard header.count >= 11, header[0].contains("订单号"), header[4].contains("商品名称"), header[6].contains("型号") || header[6].contains("款式") else {
            throw ValidationError.invalid("订单表头不匹配，需要订单号、时间、状态、店铺、商品名称、链接、型号款式、数量、商品金额、实付金额、运费共 11 列")
        }
        var orders: [TaobaoOrder] = []
        var indices: [String: Int] = [:]
        var currentOrderID = ""
        for row in rows.dropFirst(headerIndex + 1) {
            func cell(_ column: Int) -> String { row.indices.contains(column) ? row[column].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            if !cell(0).isEmpty { currentOrderID = cell(0) }
            guard !currentOrderID.isEmpty, !cell(4).isEmpty else { continue }
            guard currentOrderID.count <= 80, !currentOrderID.contains(where: { $0.isNewline }), !currentOrderID.contains(" / 商品 ") else {
                throw ValidationError.invalid("订单号格式无效")
            }
            let index: Int
            if let existing = indices[currentOrderID] { index = existing }
            else {
                index = orders.count
                indices[currentOrderID] = index
                orders.append(TaobaoOrder(orderId: currentOrderID, orderTime: cell(1), orderStatus: cell(2), shopName: cell(3), totalPaid: try price(cell(9)), shipping: try price(cell(10)), items: [], rawPaid: cell(9), rawShipping: cell(10)))
            }
            let order = orders[index]
            let style = parseStyleSpec(cell(6))
            let quantity = cell(7).isEmpty ? 1 : Int(cell(7))
            guard let quantity, quantity > 0, quantity <= 10000 else { throw ValidationError.invalid("商品“\(cell(4))”的数量无效") }
            let item = TaobaoOrderItem(orderId: currentOrderID, lineIndex: order.items.count, orderTime: order.orderTime, shopName: order.shopName, name: cell(4), productURL: cell(5), styleSpec: cell(6), quantity: quantity, price: try price(cell(8)), parsedType: style.type, parsedSize: style.size, parsedColor: style.color, rawPrice: cell(8))
            orders[index].items.append(item)
        }
        return orders
    }

    private static func price(_ text: String) throws -> Double {
        let cleaned = text.replacingOccurrences(of: "￥", with: "").replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return 0 }
        guard let value = Double(cleaned), value.isFinite, value >= 0 else { throw ValidationError.invalid("订单金额“\(text)”无效，请检查 Excel 文件") }
        return value
    }

    static func parseStyleSpec(_ text: String) -> (type: String?, size: String?, color: String?) {
        var cleaned = text
        for pattern in ["【[^】]*】", "\\[[^\\]]*\\]", "\\{[^}]*\\}", "<[^>]*>", "[（(][^）)]*(?:尾款|定金|不单售|备注|售后)[^）)]*[）)]", "·(?:尾款|定金|现货)", "β款", "色码以定金为准", "[一二三四五六七八九十\\d]+[批团]", "(?:仅|只)?(?:定-?金|尾款|现货|预约|全款|意向金)", "(?:自行)?备注尺码|尺码(?:请)?备注|单品尺码请备注", "(?:发货|收货)[^;/]*地址[^;/]*", "(?:注意|需要?有|还?需补)[^;/]*", "\\d+\\.\\d+(?:晚上|上午|下午)?[^;/]{0,10}", "\\d+月\\d+日[^;/]*", "本体|正常长度|不退不换不售后|按拍付顺序发|物流情况|年前年后", "福袋[^;/]*", "仅[^;/]*期间[^;/]*", "单品[^;/]*请?备注"] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        var type: String?, size: String?, color: String?
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ";/ ").union(.whitespacesAndNewlines)).flatMap { $0.components(separatedBy: "--") }.filter { !$0.isEmpty }
        for var part in parts {
            if part.range(of: "^(Lady\\d+|\\d{2,3}|XS|XXXL|XXL|2XL|3XL|XL|S|M|L|F|均码)$", options: [.regularExpression, .caseInsensitive]) != nil {
                if size == nil { size = part }
                continue
            }
            if let range = part.range(of: "^(Lady\\d+|XXXL|XXL|2XL|3XL|XS|XL|S|M|L)(?=[^A-Za-z]|OP|JSK|SK)", options: [.regularExpression, .caseInsensitive]) {
                if size == nil { size = String(part[range]) }
                part.removeSubrange(range)
            }
            if let keyword = typeKeywords.sorted(by: { $0.count > $1.count }).first(where: { part.range(of: $0, options: .caseInsensitive) != nil }) {
                if type == nil { type = keyword }
                let remaining = part.replacingOccurrences(of: keyword, with: "", options: .caseInsensitive)
                if color == nil, !remaining.isEmpty { color = remaining }
            } else if color == nil { color = part }
        }
        return (type, size, color)
    }

    static let typeKeywords = ["OP", "JSK", "SK", "SET", "FS", "开襟OP", "堆褶OP", "堆褶开襟OP", "拼色SK", "罩裙", "半裙", "格裙", "长裙", "连衣裙", "Fullset", "华丽套装", "衬衫", "上衣", "外套", "长外套", "大衣", "罩衫", "斗篷", "罩衫斗篷", "胸衣", "蝙蝠胸衣", "短裤", "南瓜裤", "头饰", "蝴蝶结头饰", "帽子", "贝雷帽", "KC", "发箍", "发带", "发夹", "边夹", "头纱", "腰封", "拖尾腰封", "印花钢骨腰封", "手袖", "接袖", "袖子", "包", "包包", "吊坠", "项链", "耳环", "戒指", "胸针"]

    private static func parseXML(_ data: Data, delegate: XMLParserDelegate) throws {
        // XLSX does not need DTDs or entities. Reject declarations before XMLParser sees them.
        guard let decoded = String(data: data, encoding: .utf8) else { throw ValidationError.invalid("Excel XML 编码不支持，请重新导出为 .xlsx 文件") }
        let text = decoded.uppercased()
        guard !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else { throw ValidationError.invalid("Excel 包含不支持的 XML 声明") }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw ValidationError.invalid("Excel XML 内容损坏") }
    }
}

private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var value = ""
    private var readingText = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "si" { value = "" }
        if elementName == "t" { readingText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if readingText { value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { readingText = false }
        if elementName == "si" { strings.append(value) }
    }
}

private final class WorkbookDelegate: NSObject, XMLParserDelegate {
    var firstSheetRelationshipID: String?
    var date1904 = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "sheet", firstSheetRelationshipID == nil { firstSheetRelationshipID = attributeDict["r:id"] }
        if elementName == "workbookPr" { date1904 = ["1", "true"].contains(attributeDict["date1904"] ?? "") }
    }
}

private final class RelationshipsDelegate: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "Relationship", attributeDict["TargetMode"] != "External", let id = attributeDict["Id"], let target = attributeDict["Target"] { targets[id] = target }
    }
}

private final class WorksheetDelegate: NSObject, XMLParserDelegate {
    let sharedStrings: [String]
    let date1904: Bool
    var rows: [[String]] = []
    var failure: Error?
    private var row = Array(repeating: "", count: 11)
    private var column = 0
    private var nextColumn = 0
    private var cellType = ""
    private var value = ""
    private var readingValue = false
    init(sharedStrings: [String], date1904: Bool) { self.sharedStrings = sharedStrings; self.date1904 = date1904 }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "row": row = Array(repeating: "", count: 11); nextColumn = 0
        case "c":
            let letters = (attributeDict["r"] ?? "").prefix(while: { $0.isLetter })
            guard letters.count <= 3, letters.utf8.allSatisfy({ (65...90).contains($0) }) else {
                failure = ValidationError.invalid("Excel 单元格位置无效"); parser.abortParsing(); return
            }
            column = letters.isEmpty ? nextColumn : letters.utf8.reduce(0) { $0 * 26 + Int($1) - 64 } - 1
            nextColumn = column + 1
            cellType = attributeDict["t"] ?? ""
            value = ""
        case "v", "t": readingValue = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if readingValue { value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" { readingValue = false }
        if elementName == "c", (0..<11).contains(column) {
            if cellType == "s" {
                guard let index = Int(value), sharedStrings.indices.contains(index) else {
                    failure = ValidationError.invalid("Excel 文本索引无效"); parser.abortParsing(); return
                }
                row[column] = sharedStrings[index]
            } else if column == 1, cellType.isEmpty || cellType == "n", let serial = Double(value), serial.isFinite, (1...100000).contains(serial) {
                // Excel numeric dates use a local, timezone-free calendar, with an optional 1904 epoch.
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let epoch = calendar.date(from: DateComponents(year: date1904 ? 1904 : 1899, month: date1904 ? 1 : 12, day: date1904 ? 1 : 30))!
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                row[column] = formatter.string(from: epoch.addingTimeInterval((serial * 86400).rounded()))
            } else if column == 0, cellType.isEmpty || cellType == "n", value.lowercased().contains("e") {
                let decimal = NSDecimalNumber(string: value, locale: Locale(identifier: "en_US_POSIX"))
                row[column] = decimal == .notANumber ? value : decimal.stringValue
            } else { row[column] = value }
        }
        if elementName == "row" {
            if Task.isCancelled { parser.abortParsing(); return }
            guard rows.count < 100000 else { failure = ValidationError.invalid("订单超过 10 万行，请分批导入"); parser.abortParsing(); return }
            rows.append(row)
        }
    }
}
