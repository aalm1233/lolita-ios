import SwiftUI

struct PurchaseReviewShortcut: View {
    @AppStorage("showTotalPrice") private var showAmount = true
    @State private var reviews: [PurchaseReview] = []
    var body: some View {
        VStack(spacing: 0) {
            if showAmount, !reviews.isEmpty {
                NavigationLink { PurchaseReviewScreen() } label: {
                    LolitaCard(variant: .compact) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("待核对购买资料").font(.subheadline.weight(.medium))
                                Text("\(reviews.count) 件服饰与小物 · 查看清单").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            SkinIcon(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("purchase-review-shortcut")
            }
        }.task { for await value in PurchaseReviewRepository(db: AppModule.shared.db.dbQueue).observe() { guard !Task.isCancelled else { return }; reviews = value } }
    }
}

struct PurchaseReviewScreen: View {
    @State private var reviews: [PurchaseReview] = []
    @State private var loaded = false
    @State private var search = ""
    var body: some View {
        List {
            Text("仅列出待补或待核对的购买资料；核对前不会修改拥有状态、原付款或照片。")
                .font(.caption).foregroundStyle(.secondary)
            if !loaded { ProgressView("正在读取清单…") }
            else if reviews.isEmpty { Text("购买资料已核对完成") }
            ForEach(reviews.filter { search.isEmpty || $0.item.name.localizedCaseInsensitiveContains(search) }) { review in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { ItemDetailScreen(itemId: review.id) } label: {
                        HStack {
                            LolitaThumbnail(path: review.item.imageUrls.values.first, symbol: "hanger", width: 42, height: 52)
                            Text(review.item.name).foregroundStyle(.primary)
                        }
                    }
                    Text(review.reason).font(.caption).foregroundStyle(.secondary)
                    NavigationLink(review.orderItemId == review.id ? "核对购买订单" : "核对主件购买订单") { PriceManageScreen(itemId: review.orderItemId) }
                        .accessibilityIdentifier("review-order-\(review.id)")
                }.padding(.vertical, 6)
            }
        }.searchable(text: $search, prompt: "搜索服饰名称")
            .lolitaNavBar(title: "待核对购买资料", showBack: true)
            .task { for await value in PurchaseReviewRepository(db: AppModule.shared.db.dbQueue).observe() { guard !Task.isCancelled else { return }; reviews = value; loaded = true } }
    }
}
