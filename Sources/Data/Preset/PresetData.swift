import Foundation
import GRDB

enum PresetData {
    static let styles = [
        "甜系", "古典", "哥特", "田园", "中华", "其他"
    ]

    static let seasons = [
        "春", "夏", "秋", "冬", "四季"
    ]

    static let categories: [(name: String, group: CategoryGroup)] = [
        // CLOTHING
        ("JSK", .clothing),
        ("OP", .clothing),
        ("SK", .clothing),
        ("衬衫", .clothing),
        ("内搭", .clothing),
        ("外套", .clothing),
        ("裤装", .clothing),
        ("套装", .clothing),
        ("其他服饰", .clothing),
        // ACCESSORY
        ("头饰", .accessory),
        ("项链", .accessory),
        ("手饰", .accessory),
        ("袜子", .accessory),
        ("鞋子", .accessory),
        ("包", .accessory),
        ("伞", .accessory),
        ("其他配饰", .accessory),
    ]

    static let brands: [String] = [
        "Angelic Pretty",
        "Baby, The Stars Shine Bright",
        "Metamorphose temps de fille",
        "Innocent World",
        "Mary Magdalene",
        "Victorian Maiden",
        "Juliette et Justine",
        "Millefleurs",
        "Atelier Pierrot",
        "Sheglit",
        "Moi-même-Moitié",
        "Alice and the Pirates",
        "Triple Fortune",
        "Excentrique",
        "Milk",
        "Jane Marple",
        "Emily Temple Cute",
        "Shirley Temple",
        "Maxicimam",
        "Putumayo",
        "h.NAOTO",
        "Heart E",
        "Dear Celine",
        "Leur Getter",
        "Liz Lisa",
        "Ank Rouge",
        "Secret Honey",
        "Rose Marie Seoir",
        "Chérie Cerise",
        "Amavel",
        "Fint",
        "Axes Femme",
        "Katie",
        "Xian Yin",
        "Infanta",
        "To Alice",
        "Surface Spell",
        "ZJ Story",
        "Hinana queena",
        "Ksana",
        "Henrietta",
        "Bacio Bouquet",
        "Elpress L",
        "Miss Point",
        "CC Cat",
        "Faeries Daffodil",
        "Ozz On",
        "Neverland",
        "Ying Luo Fu",
        "Zhi Yu Ji",
        "Dark Star Island",
        "Elf Village",
        "Little Dipper",
        "Rose Museum",
        "Forest Wardrobe",
        "Sakura Panda",
        "An Nuoli",
        "Xing Yue Meng",
        "Pinklight",
        "Magical Doll",
        "Meng Yu",
        "Red Maria",
        "Liang Xian",
        "Nan Lu",
        "Hua Hui",
        "Xiao Shu Niang",
        "Xue Yang",
        "San Xian",
        "Lu Lu",
        "Tang Guoguo",
        "Mu Yao",
        "Miao Wu",
        "Xia Yu",
        "Xue Shan",
        "Mo Yan",
        "Xiao Xiong",
        "Mao Mao",
        "Tu Zi",
        "Hai Tun",
        "Xing Xing",
        "Yue Liang",
        "Tai Yang",
        "Yun Duo",
        "Hua Duo",
        "Cao Mei",
        "Ying Tao",
        "Pu Tao",
        "Mang Guo",
        "Ning Meng",
        "Lan Mei",
        "Tao Zi",
        "Xiang Jiao",
        "Xi Gua",
    ]
}

extension PresetData {
    static func seed(_ db: Database) throws {
            for brand in PresetData.brands {
                var b = Brand(name: brand, isPreset: true)
                try b.insert(db, onConflict: .ignore)
            }
            for cat in PresetData.categories {
                var c = Category(name: cat.name, group: cat.group, isPreset: true)
                c.categorySemantic = CategorySemantic.historical(cat.name)
                if try db.columns(in: "categories").contains(where: { $0.name == "categorySemantic" }) {
                    try c.insert(db, onConflict: .ignore)
                } else {
                    try db.execute(sql: "INSERT OR IGNORE INTO categories(name, \"group\", isPreset, createdAt) VALUES (?, ?, 1, ?)", arguments: [c.name, c.group.rawValue, c.createdAt])
                }
            }
            for style in PresetData.styles {
                var s = Style(name: style, isPreset: true)
                try s.insert(db, onConflict: .ignore)
            }
            for name in ["淘宝", "闲鱼", "线下", "其他"] {
                var source = Source(name: name, isPreset: true)
                try source.insert(db, onConflict: .ignore)
            }
            for season in PresetData.seasons {
                var s = Season(name: season, isPreset: true)
                try s.insert(db, onConflict: .ignore)
            }
    }
}
