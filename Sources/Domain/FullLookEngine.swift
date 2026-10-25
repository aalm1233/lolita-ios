import Foundation

struct LookOption: Sendable {
    let item: Item
    let score: Int
    let reasons: [String]
}

struct LookGroup: Identifiable, Sendable {
    let id: String
    let options: [LookOption]
}

/// Stable category types survive user renames; unresolved custom types keep their own slot.
enum FullLookEngine {
    static func role(_ category: Category) -> String {
        switch category.categorySemantic {
        case .jsk, .op, .sk: return "主裙"
        case .blouse: return "上衣"
        case .outerwear, .cape, .shawl: return "外搭"
        case .kc, .bonnet, .headband, .hair_clip, .hat: return "头饰"
        default: break
        }
        switch category.categorySemantic.profile {
        case "hosiery": return "袜子"
        case "footwear": return "鞋子"
        case "bag": return "包袋"
        default: break
        }
        // Historical ambiguous types must not be rewritten to infer a matching role.
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["jsk", "op", "sk", "连衣裙", "半裙", "裙子"].contains(name) { return "主裙" }
        if ["kc", "bonnet", "发带", "其他头饰", "头饰", "帽子", "发夹"].contains(name) { return "头饰" }
        if name.contains("衬衫") || name.contains("上衣") || name == "blouse" { return "上衣" }
        if name.contains("袜") { return "袜子" }
        if name.contains("鞋") { return "鞋子" }
        if name.contains("包") { return "包袋" }
        if ["斗篷", "披肩", "外套", "开衫"].contains(name) { return "外搭" }
        return category.name
    }

    static func build(target: Item, candidates: [Item], categories: [Category], history: Set<Int64>) -> [LookGroup] {
        let catalog = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        guard let main = catalog[target.categoryId] else { return [] }
        let targetRole = role(main)
        let isOP = main.categorySemantic == .op || (main.categorySemantic == .unconfirmed && main.name.uppercased() == "OP")
        var seen = Set<Int64>()
        var groups: [String: [LookOption]] = [:]
        for item in candidates where item.id != target.id && item.status == .owned && seen.insert(item.id).inserted {
            guard let category = catalog[item.categoryId] else { continue }
            let slot = role(category)
            guard slot != targetRole, slot != "主裙", !(isOP && slot == "上衣") else { continue }
            var reasons: [String] = []
            if let style = target.style, !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, style == item.style { reasons.append("风格相同") }
            if !Set(target.colors.values).intersection(item.colors.values).isEmpty { reasons.append("颜色呼应") }
            let seasons = tokens(target.season), other = tokens(item.season)
            if !seasons.intersection(other).isEmpty || (!seasons.isEmpty && other.contains("四季")) || (!other.isEmpty && seasons.contains("四季")) { reasons.append("季节适合") }
            if history.contains(item.id) { reasons.append("曾经一起搭配") }
            let score = reasons.count + (history.contains(item.id) ? 2 : 0)
            groups[slot, default: []].append(LookOption(item: item, score: score, reasons: reasons.isEmpty ? ["补齐\(slot)，可自行替换"] : reasons))
        }
        let order = ["上衣", "外搭", "头饰", "袜子", "鞋子", "包袋"]
        return groups.map { LookGroup(id: $0.key, options: $0.value.sorted { $0.score == $1.score ? $0.item.id < $1.item.id : $0.score > $1.score }) }
            .sorted { left, right in
                let a = order.firstIndex(of: left.id) ?? order.count, b = order.firstIndex(of: right.id) ?? order.count
                return a == b ? left.id < right.id : a < b
            }
    }
    private static func tokens(_ value: String?) -> Set<String> {
        Set((value ?? "").replacingOccurrences(of: "，", with: ",").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}

struct LookSelection: Sendable {
    var selected: [String: Int64] = [:]
    var locked: Set<String> = []
    init(groups: [LookGroup] = []) {
        selected = Dictionary(uniqueKeysWithValues: groups.compactMap { group in group.options.first.map { (group.id, $0.item.id) } })
    }
    mutating func next(groups: [LookGroup]) {
        for group in groups where !locked.contains(group.id) {
            guard let id = selected[group.id], !group.options.isEmpty else { continue }
            let position = group.options.firstIndex { $0.item.id == id } ?? -1
            selected[group.id] = group.options[(position + 1) % group.options.count].item.id
        }
    }
}
