import SwiftUI

struct LolitaThumbnail: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let path: String?
    var symbol: String = "photo"
    var width: CGFloat = 64
    var height: CGFloat = 80

    private var accent: Color {
        colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor
    }

    var body: some View {
        ZStack {
            accent.opacity(0.08)
            if let path, !path.isEmpty {
                LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path))
            } else {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(accent.opacity(0.6))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS))
        .accessibilityHidden(true)
    }
}

struct LolitaBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct LolitaCollectionRow: View {
    let title: String
    var subtitle: String = ""
    var imagePath: String? = nil
    var symbol: String = "photo"

    var body: some View {
        HStack(spacing: 14) {
            LolitaThumbnail(path: imagePath, symbol: symbol)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

struct LolitaEmptyState: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let message: String
    let systemImage: String
    var fillsAvailableSpace: Bool = true

    private var accent: Color {
        colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(accent)
                .frame(width: 76, height: 76)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: fillsAvailableSpace ? .infinity : nil)
    }
}

struct LolitaCollectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text("\(count) 项").font(.caption).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// Skin-aware tabs use SwiftUI drawing, so the same view can be previewed offline.
struct LolitaSegmentedTabs<Selection: Hashable>: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    private var accent: Color {
        colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
                    ForEach(options, id: \.self) { option in tab(option) }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(options, id: \.self) { option in tab(option) }
                }
            }
        }
        .padding(4)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM))
    }

    private func tab(_ option: Selection) -> some View {
        Button { selection = option } label: {
            Text(label(option))
                .font(.subheadline.weight(selection == option ? .semibold : .regular))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(selection == option ? accent : .secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                .background {
                    if selection == option {
                        RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS)
                            .fill(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
                            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }
}

extension View {
    @ViewBuilder func lolitaCollectionListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .contentMargins(.top, 4, for: .scrollContent)
        #else
        self.listStyle(.inset)
        #endif
    }

    func lolitaCollectionRowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

/// Android-style page tabs; collection filters keep the separate segmented control.
struct LolitaPageTabs<Selection: Hashable>: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    private var accent: Color { colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        VStack(spacing: 9) {
                            Text(label(option))
                                .font(.subheadline.weight(selection == option ? .semibold : .regular))
                                .foregroundStyle(selection == option ? accent : .secondary)
                                .padding(.horizontal, 2)
                            Capsule().fill(selection == option ? accent : .clear).frame(height: 3)
                        }
                        .padding(.top, 12)
                        .frame(minWidth: 48, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(accent.opacity(0.1)).frame(height: 0.5) }
    }
}

enum LolitaCollectionViewMode: String, CaseIterable {
    case list, grid, compactGrid, gallery
    var title: String {
        switch self { case .list: return "列表"; case .grid: return "两列网格"; case .compactGrid: return "三列网格"; case .gallery: return "画廊" }
    }
    var symbol: String {
        switch self { case .list: return "rectangle.grid.1x2"; case .grid: return "square.grid.2x2"; case .compactGrid: return "square.grid.3x3"; case .gallery: return "photo.on.rectangle.angled" }
    }
    var columns: Int { self == .list ? 1 : self == .compactGrid ? 3 : 2 }
}

struct LolitaCollectionControls: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    var count: Int
    var unit: String = "件"
    var detail: String = ""
    var totalPrice: Double? = nil
    @Binding var mode: LolitaCollectionViewMode

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(count) \(unit)").font(.subheadline.weight(.semibold)).monospacedDigit()
                if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            if let totalPrice, totalPrice > 0 {
                Text("合计 \(lolitaPriceLabel(totalPrice))")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor)
            }
            Menu {
                Picker("展示方式", selection: $mode) {
                    ForEach(LolitaCollectionViewMode.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                Image(systemName: mode.symbol).font(.system(size: 17)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("展示方式：\(mode.title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
    }
}

func lolitaPriceLabel(_ amount: Double) -> String {
    "¥" + amount.formatted(.number.precision(.fractionLength(0...2)))
}

struct LolitaCollectionGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var mode: LolitaCollectionViewMode
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : mode.columns), alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
    }
}

/// Give every photo an explicit viewport, independent of its original dimensions.
struct LolitaCollectionImage: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    var path: String?
    var title: String
    var symbol: String = "photo"
    var ratio: CGFloat = 0.8

    private var accent: Color { colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor }
    var body: some View {
        Rectangle().fill(.clear).aspectRatio(ratio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        LinearGradient(colors: [accent.opacity(0.2), accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        if let path, !path.isEmpty {
                            LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path))
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: symbol).font(.system(size: 30, weight: .light))
                                Text(String(title.prefix(1))).font(.title.weight(.medium))
                            }
                            .foregroundStyle(accent.opacity(0.65))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
            }
            .accessibilityHidden(true)
    }
}

struct LolitaImageLabel: View {
    var text: String
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).monospacedDigit()
            .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct LolitaItemStatus: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    var item: Item
    var color: Color {
        if item.status == .pendingBalance { return colorScheme == .dark ? .yellow : .orange }
        if item.status == .wished {
            switch item.priority { case .high: return .pink; case .medium: return colorScheme == .dark ? .yellow : .orange; case .low: return .green }
        }
        return colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor
    }
    var text: String {
        switch item.status {
        case .owned: return "已拥有"
        case .pendingBalance: return "待尾款"
        case .wished:
            switch item.priority { case .high: return "高优先"; case .medium: return "中优先"; case .low: return "低优先" }
        }
    }
    var body: some View { LolitaBadge(text: text, color: color) }
}

struct ItemCollectionCard: View {
    var item: Item
    var brandName: String? = nil
    var categoryName: String? = nil
    var price: Double? = nil
    var mode: LolitaCollectionViewMode = .grid

    private var details: String {
        [categoryName, item.size, item.colors.values.first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        LolitaCard(variant: .gallery) {
            if mode == .list {
                ItemRow(item: item, brandName: brandName, categoryName: categoryName, price: price, showsDescription: true)
                    .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    LolitaCollectionImage(path: item.imageUrls.values.first, title: item.name, symbol: "tshirt", ratio: mode == .gallery ? 0.75 : 0.8)
                        .overlay(alignment: .topTrailing) {
                            if let price, price > 0 { LolitaImageLabel(text: lolitaPriceLabel(price)).padding(7) }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if mode == .gallery {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    if let brandName { Text(brandName).font(.caption2).opacity(0.85).lineLimit(1) }
                                    if !details.isEmpty { Text(details).font(.caption2).opacity(0.8).lineLimit(1) }
                                }
                                .foregroundStyle(.white).padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 30)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                    if mode != .gallery {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            if let brandName { Text(brandName).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            if !details.isEmpty { Text(details).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            LolitaItemStatus(item: item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    }
                }
            }
        }
    }
}

struct LolitaLinkedItemImages: View {
    var items: [Item]
    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(items.prefix(4)), id: \.id) { item in
                LolitaThumbnail(path: item.imageUrls.values.first, symbol: "tshirt", width: 25, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.8), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

struct CoordinateCollectionCard: View {
    var coordinate: Coordinate
    var items: [Item] = []
    var price: Double? = nil
    var mode: LolitaCollectionViewMode = .grid

    var body: some View {
        LolitaCard(variant: .gallery) {
            if mode == .list {
                HStack(spacing: 12) {
                    LolitaThumbnail(path: coordinate.imageUrls.values.first, symbol: "photo.on.rectangle.angled", width: 80, height: 96)
                    information
                }.padding(12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    LolitaCollectionImage(path: coordinate.imageUrls.values.first ?? items.compactMap { $0.imageUrls.values.first }.first,
                                          title: coordinate.name, symbol: "photo.on.rectangle.angled")
                        .overlay(alignment: .topLeading) { LolitaImageLabel(text: "\(items.count) 件").padding(7) }
                        .overlay(alignment: .topTrailing) {
                            if let price, price > 0 { LolitaImageLabel(text: lolitaPriceLabel(price)).padding(7) }
                        }
                    information.padding(9)
                }
            }
        }
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(coordinate.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            if !coordinate.description.isEmpty { Text(coordinate.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack(spacing: 8) {
                Text("\(items.count) 件服饰").font(.caption2).foregroundStyle(.secondary)
                if mode == .list, let price, price > 0 { Text(lolitaPriceLabel(price)).font(.caption.weight(.semibold)).foregroundStyle(.primary) }
            }
            if !items.isEmpty { LolitaLinkedItemImages(items: items) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OutfitLogCollectionCard: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    var log: OutfitLog
    var items: [Item] = []
    private var date: Date { Date(timeIntervalSince1970: TimeInterval(log.date) / 1000) }
    private var accent: Color { colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor }

    var body: some View {
        LolitaCard(variant: .gallery) {
            VStack(alignment: .leading, spacing: 0) {
                if let path = log.imageUrls.values.first {
                    LolitaCollectionImage(path: path, title: "穿搭", symbol: "figure.stand", ratio: 1.5)
                        .overlay(alignment: .topLeading) {
                            Text(date.formatted(.dateTime.month().day().weekday()))
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(accent.opacity(0.9), in: UnevenRoundedRectangle(bottomTrailingRadius: 12))
                        }
                } else {
                    Text(date.formatted(.dateTime.month().day().weekday()))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.08))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(log.note.isEmpty ? "今天的搭配" : log.note).font(.subheadline).foregroundStyle(.primary).lineLimit(3)
                    HStack(spacing: 12) {
                        Label("\(log.imageUrls.values.count) 张", systemImage: "photo").font(.caption2).foregroundStyle(.secondary)
                        Label("\(items.count) 件", systemImage: "tshirt").font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !items.isEmpty { LolitaLinkedItemImages(items: items) }
                    }
                }.padding(12)
            }
        }
    }
}

extension View {
    func lolitaCardListStyle() -> some View {
        listStyle(.plain).scrollContentBackground(.hidden)
    }
    func lolitaCardRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}
