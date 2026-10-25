import Foundation
import GRDB

enum PresetData {
    static let styles = [
        "甜系", "古典", "哥特", "田园", "中华", "其他"
    ]

    static let seasons = [
        "春", "夏", "秋", "冬", "四季"
    ]

    static let categories: [(name: String, group: CategoryGroup)] = {
        let legacy: [(name: String, group: CategoryGroup)] = [
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
        return legacy + CategorySemantic.allCases.filter { semantic in
            semantic != .unconfirmed && !legacy.contains { $0.name == semantic.label }
        }.map { ($0.label, $0.profile == "clothing" || $0 == .petticoat ? .clothing : .accessory) }
    }()

    // Current Android BrandRepository.ensurePresetBrands; regenerate with sync_builtin_library.py.
    static let brands: [String] = [
        "古典玩偶（Classical Puppets）",
        "仲夏物语（Elpress L）",
        "玻璃纸之夜（NDC）",
        "摇篮曲（Lullaby）",
        "圆点点小姐 Lolita 洋服社",
        "小宝石洋服（Petit Bijou）",
        "表面咒语（Surface Spell）",
        "酒心可可（Chocolate Lovers）",
        "花与珍珠匣",
        "莉莉子 Lolita",
        "新路德维希（Neo Ludwig）",
        "CuteQ",
        "纪念岛",
        "Nololita",
        "平成魔女",
        "七愚",
        "织锦园",
        "无名诗（东之森）",
        "白雪姬 Lolita",
        "樱桃爆弹",
        "告白气球家",
        "绵羊泡芙（Sheep Puff）",
        "Honey Honey Lolita",
        "沉默编织",
        "悠尼蒂鹿（Unideer）",
        "JS 洋装贩售",
        "暗星之岛",
        "晴木",
        "银河有迹可循",
        "玻璃花信",
        "十二月暖暖",
        "九歌 Lolita",
        "ALICE GIRL 原创工作室",
        "小熊星座洋服",
        "果鹿 Lolita",
        "四叶工房",
        "Precious Clove",
        "IchigoMikou",
        "Pink up Lolita",
        "Morning Glory 原创设计",
        "鹿隐洋装",
        "樱洛芙",
        "Choker Rabbit（CR）",
        "星芙颂",
        "浮世镜",
        "月亮浮士德",
        "朝鹿",
        "榛果可可花束",
        "星夜彩虹",
        "梦境人偶",
        "奶油橘喵酱",
        "星辰猫 Lolita",
        "甜心贩售机",
        "猫咪杀手工作室",
        "魔法裙子猫",
        "雾雨风",
        "海月社",
        "风之诗 Lolita",
        "幽夜森林",
        "月光酒馆",
        "蒲公英的约定",
        "绮丽梦境",
        "天使之书",
        "蔷薇十字",
        "胡桃夹子 Lolita",
        "糖果匣子",
        "落日情书",
        "微光之晨",
        "云间月",
        "山茶与兔",
        "Angelic Pretty（AP）",
        "Baby, the Stars Shine Bright（BABY）",
        "Alice and the Pirates（ANP）",
        "Innocent World（IW）",
        "Metamorphose Temps de Fille（Meta）",
        "Victorian Maiden",
        "Juliette et Justine（JEJ）",
        "Mary Magdalene（MM）",
        "Atelier Boz",
        "Atelier Pierrot",
        "Moi-même-Moitié（MmM）",
        "Jane Marple",
        "Emily Temple Cute",
        "Pink House",
        "Bodyline",
        "Antique Beast",
        "Excentrique",
        "Heart E",
        "Millefleurs",
        "Putumayo",
        "h.NAOTO",
        "MAXICIMAM",
        "Grimoire",
        "Sheglit",
        "MILK",
        "Chocochip Cookie",
        "Triple Fortune",
        "Royal Princess Alice",
        "Enchantlic Enchantilly",
        "Q-pot.",
        "Physical Drop",
        "Fairy Wish",
        "Leur Getter",
        "Aria",
        "Chantilly",
        "Lyrical Bunny",
        "Honey Cake",
        "Milk Cocoa",
        "Sugar Dream",
        "Black Peace Now",
        "Listen Flavor",
        "Kinji",
        "Angelic Imprint",
        "Princess Puff",
        "Misty Rose",
        "Lilac Time",
        "Rose Cross",
        "Velvet Opera",
        "Crystal Doll",
        "Silver Rain",
        "Starry Night",
        "Gothic Lolita Wigs（服饰线）",
        "Sweet Devil",
        "Dark Rose",
        "White Swan",
        "Red Ribbon",
        "Blue Bird",
        "Golden Crown",
        "Purple Butterfly",
        "Green Garden",
        "Chantilly Korea",
        "Lace Market（自有线）",
        "Angelic Pretty Korea（韩线）",
        "Baby Korea",
        "Metamorphose Korea",
        "Lolita Collective",
        "Victorian Rose",
        "Gothic Angel",
        "Sweet Lolita Land",
        "Dark Lolita Couture",
        "Princess Lolita",
        "Elegant Lolita",
        "Romantic Lolita",
        "Classic Lolita Co.",
        "Pastel Lolita",
        "Gothic Princess",
        "Sweetheart Lolita",
        "Lace & Ribbon",
        "Bow & Bustle",
        "Ruffled Romance",
        "Velvet & Lace",
        "Satin & Silk",
        "Cotton Candy Lolita",
        "Strawberry Shortcake",
        "Cherry Blossom Lolita",
        "Lavender Dream",
        "Mint Chocolate",
        "Peach Parfait",
        "Blueberry Muffin",
        "Raspberry Tart",
        "Blackberry Sorbet",
        "Plum Pudding",
        "Apple Pie",
        "Orange Marmalade",
        "Lemon Tart",
        "Grape Jelly",
        "Pineapple Upside Down",
        "Coconut Cream",
        "Vanilla Bean",
        "Chocolate Mousse",
        "Gothic Lolita Couture",
        "Lolita Fashion Co.",
        "Cute Lolita",
        "Pretty Lolita",
        "Lovely Lolita",
        "Adorable Lolita",
        "Charming Lolita",
        "Delightful Lolita",
        "Enchanting Lolita",
        "Fascinating Lolita",
        "Gorgeous Lolita",
        "Heavenly Lolita",
        "Irresistible Lolita",
        "Joyful Lolita",
        "Kind Lolita",
        "Lively Lolita",
        "Magical Lolita",
        "Nice Lolita",
        "Outstanding Lolita",
        "Perfect Lolita",
        "Quaint Lolita",
        "Radiant Lolita",
        "Shining Lolita",
        "Tender Lolita",
        "Unique Lolita",
        "Vivacious Lolita",
        "Wonderful Lolita",
        "Xquisite Lolita",
        "Youthful Lolita",
        "Zesty Lolita",
        "OZZ on japan",
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
