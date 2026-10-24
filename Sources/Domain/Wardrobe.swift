import Foundation
import GRDB

enum ItemComposition: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case unconfirmed = "UNCONFIRMED", single = "SINGLE", pair = "PAIR", set = "SET"
    var label: String { switch self { case .unconfirmed: "组合不明"; case .single: "单只／单件"; case .pair: "成双"; case .set: "成组" } }
}

enum CategorySemantic: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case unconfirmed = "UNCONFIRMED"
    case jsk = "JSK"
    case op = "OP"
    case sk = "SK"
    case blouse = "BLOUSE"
    case trousers = "TROUSERS"
    case outerwear = "OUTERWEAR"
    case cape = "CAPE"
    case shawl = "SHAWL"
    case petticoat = "PETTICOAT"
    case other_clothing = "OTHER_CLOTHING"
    case full_wig = "FULL_WIG"
    case hair_piece = "HAIR_PIECE"
    case bangs_piece = "BANGS_PIECE"
    case ponytail = "PONYTAIL"
    case braid = "BRAID"
    case short_socks = "SHORT_SOCKS"
    case mid_socks = "MID_SOCKS"
    case knee_socks = "KNEE_SOCKS"
    case over_knee_socks = "OVER_KNEE_SOCKS"
    case tights = "TIGHTS"
    case leg_warmers = "LEG_WARMERS"
    case other_hosiery = "OTHER_HOSIERY"
    case mary_jane = "MARY_JANE"
    case tea_party_shoes = "TEA_PARTY_SHOES"
    case pumps = "PUMPS"
    case ankle_boots = "ANKLE_BOOTS"
    case long_boots = "LONG_BOOTS"
    case other_footwear = "OTHER_FOOTWEAR"
    case kc = "KC"
    case bonnet = "BONNET"
    case headband = "HEADBAND"
    case hair_clip = "HAIR_CLIP"
    case hat = "HAT"
    case necklace = "NECKLACE"
    case earring = "EARRING"
    case brooch = "BROOCH"
    case waist_accessory = "WAIST_ACCESSORY"
    case wrist_cuffs = "WRIST_CUFFS"
    case gloves = "GLOVES"
    case other_accessory = "OTHER_ACCESSORY"
    case handbag = "HANDBAG"
    case crossbody_bag = "CROSSBODY_BAG"
    case backpack = "BACKPACK"
    case clutch = "CLUTCH"
    case other_bag = "OTHER_BAG"
    case parasol = "PARASOL"
    case fan = "FAN"
    case cane = "CANE"
    case doll = "DOLL"
    case bouquet = "BOUQUET"
    case other_handheld = "OTHER_HANDHELD"
    var label: String { switch self {
    case .unconfirmed: "待确认"
    case .jsk: "JSK"
    case .op: "OP"
    case .sk: "SK"
    case .blouse: "衬衫"
    case .trousers: "裤装"
    case .outerwear: "外套"
    case .cape: "斗篷"
    case .shawl: "披肩"
    case .petticoat: "裙撑"
    case .other_clothing: "其他服装"
    case .full_wig: "全头假发"
    case .hair_piece: "发片"
    case .bangs_piece: "刘海片"
    case .ponytail: "假马尾"
    case .braid: "假辫"
    case .short_socks: "短袜"
    case .mid_socks: "中筒袜"
    case .knee_socks: "及膝袜"
    case .over_knee_socks: "过膝袜"
    case .tights: "连裤袜"
    case .leg_warmers: "袜套"
    case .other_hosiery: "其他袜装"
    case .mary_jane: "玛丽珍鞋"
    case .tea_party_shoes: "茶会鞋"
    case .pumps: "浅口鞋"
    case .ankle_boots: "短靴"
    case .long_boots: "长靴"
    case .other_footwear: "其他鞋履"
    case .kc: "KC"
    case .bonnet: "Bonnet"
    case .headband: "发带"
    case .hair_clip: "发夹"
    case .hat: "帽子"
    case .necklace: "项链"
    case .earring: "耳饰"
    case .brooch: "胸针"
    case .waist_accessory: "腰饰"
    case .wrist_cuffs: "手袖"
    case .gloves: "手套"
    case .other_accessory: "其他配饰"
    case .handbag: "手提包"
    case .crossbody_bag: "斜挎包"
    case .backpack: "背包"
    case .clutch: "手拿包"
    case .other_bag: "其他包袋"
    case .parasol: "阳伞"
    case .fan: "扇子"
    case .cane: "手杖"
    case .doll: "玩偶"
    case .bouquet: "花束"
    case .other_handheld: "其他手持道具"
    } }
    var profile: String { switch self {
    case .unconfirmed: "unconfirmed"
    case .jsk: "clothing"
    case .op: "clothing"
    case .sk: "clothing"
    case .blouse: "clothing"
    case .trousers: "clothing"
    case .outerwear: "clothing"
    case .cape: "clothing"
    case .shawl: "clothing"
    case .petticoat: "petticoat"
    case .other_clothing: "clothing"
    case .full_wig: "wig"
    case .hair_piece: "wig"
    case .bangs_piece: "wig"
    case .ponytail: "wig"
    case .braid: "wig"
    case .short_socks: "hosiery"
    case .mid_socks: "hosiery"
    case .knee_socks: "hosiery"
    case .over_knee_socks: "hosiery"
    case .tights: "hosiery"
    case .leg_warmers: "hosiery"
    case .other_hosiery: "hosiery"
    case .mary_jane: "footwear"
    case .tea_party_shoes: "footwear"
    case .pumps: "footwear"
    case .ankle_boots: "footwear"
    case .long_boots: "footwear"
    case .other_footwear: "footwear"
    case .kc: "accessory"
    case .bonnet: "accessory"
    case .headband: "accessory"
    case .hair_clip: "accessory"
    case .hat: "accessory"
    case .necklace: "accessory"
    case .earring: "accessory"
    case .brooch: "accessory"
    case .waist_accessory: "accessory"
    case .wrist_cuffs: "accessory"
    case .gloves: "accessory"
    case .other_accessory: "accessory"
    case .handbag: "bag"
    case .crossbody_bag: "bag"
    case .backpack: "bag"
    case .clutch: "bag"
    case .other_bag: "bag"
    case .parasol: "handheld"
    case .fan: "handheld"
    case .cane: "handheld"
    case .doll: "handheld"
    case .bouquet: "handheld"
    case .other_handheld: "handheld"
    } }
    /// Only unambiguous historical labels are backfilled once; later renames never infer type.
    static func historical(_ name: String) -> Self {
        if let value = allCases.first(where: { $0.label.lowercased() == name.lowercased() }) { return value }
        return ["袜子": .other_hosiery, "鞋子": .other_footwear, "包": .other_bag, "伞": .parasol,
                "头饰": .other_accessory, "手饰": .other_accessory, "内搭": .other_clothing,
                "其他服饰": .other_clothing, "假发": .full_wig][name] ?? .unconfirmed
    }
}

/// Raw text preserves units, ranges and unfinished input. Switching categories retains all profiles.
struct WardrobeSpecifications: Codable, Equatable, Sendable {
    var version = 1
    var pattern = ""
    var profiles: [String: [String: String]] = [:]
    static let fields: [String: [(String, String)]] = [
        "clothing": [("lengthCm", "衣长（cm）"), ("bustCm", "胸围（cm）"), ("waistCm", "腰围（cm）"), ("hipCm", "臀围（cm）"), ("shoulderWidthCm", "肩宽（cm）"), ("sleeveLengthCm", "袖长（cm）")],
        "wig": [("mainColor", "主色"), ("lengthCm", "长度（cm）"), ("curl", "卷度"), ("extraHairPieces", "附加发片"), ("bangs", "刘海"), ("parting", "分缝"), ("material", "材质"), ("heatResistance", "耐热温度"), ("headCircumference", "头围"), ("stylingNotes", "造型备注")],
        "hosiery": [("lengthType", "袜长类型"), ("sizeText", "袜码"), ("pattern", "图案"), ("thickness", "厚度"), ("denier", "丹数"), ("footLength", "脚长"), ("material", "材质"), ("transparency", "透肤度")],
        "footwear": [("sizeText", "鞋码"), ("sizeSystem", "尺码体系"), ("heelHeightCm", "跟高（cm）"), ("innerLengthCm", "内长（cm）"), ("shaftHeightCm", "筒高（cm）"), ("toeShape", "鞋头"), ("fastening", "穿脱方式"), ("comfort", "舒适度"), ("walkingNotes", "行走备注")],
        "petticoat": [("lengthCm", "裙撑长（cm）"), ("silhouette", "轮廓"), ("volume", "蓬度"), ("waistCm", "腰围（cm）"), ("layers", "层数"), ("material", "材质"), ("notes", "备注")],
        "accessory": [("wearPosition", "佩戴位置"), ("dimensions", "尺寸"), ("fastening", "固定方式"), ("material", "材质")],
        "bag": [("carryMode", "背法"), ("dimensions", "尺寸"), ("capacity", "容量"), ("phoneFit", "手机适配"), ("material", "材质")],
        "handheld": [("usage", "用途"), ("dimensions", "尺寸"), ("foldable", "是否可折叠"), ("material", "材质")]
    ]
    func encoded() throws -> String {
        var root: [String: Any] = ["version": version, "pattern": pattern]
        for (key, value) in profiles { root[key] = value }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let text = String(decoding: data, as: UTF8.self)
        _ = try Self.decode(text)
        return text
    }
    static func decode(_ text: String) throws -> Self {
        if text.isEmpty { return Self() }
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let version = root["version"] as? NSNumber, String(cString: version.objCType) != "c", version == 1,
              Set(root.keys).isSubset(of: Set(fields.keys).union(["version", "pattern"])) else { throw ValidationError.invalid("物品规格版本或字段无效") }
        var result = Self()
        if let pattern = root["pattern"] { guard let pattern = pattern as? String, pattern.count <= 4000 else { throw ValidationError.invalid("图案说明无效") }; result.pattern = pattern }
        for (key, fields) in fields {
            if let raw = root[key] {
                guard let values = raw as? [String: String], Set(values.keys).isSubset(of: Set(fields.map(\.0))), values.values.allSatisfy({ $0.count <= 4000 }) else { throw ValidationError.invalid("专属规格无效") }
                result.profiles[key] = values
            }
        }
        return result
    }
}
