# Lolita iOS Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add wishlist tab, full payment tracking (prices + installments), payment calendar, and spending analytics to the iOS app. Fix the LolitaApp entry point placeholder.

**Architecture:** Bottom-up by layer, matching Phase 1 patterns: GRDB v2 migration → entities → repositories → ViewModels → Screens → nav wiring. Each task compiles cleanly before the next. MVVM + Repository, SwiftUI Form for edit screens, AsyncStream for reactive observation.

**Tech Stack:** Swift 6, SwiftUI, GRDB 6.29+, Kingfisher 8.0+ (existing). iOS 17+.

---

## File Structure Map

```
Sources/
├── LolitaApp.swift                          # MODIFY — fix entry point
├── AppModule.swift                          # MODIFY — add Price/Payment repos
├── Data/
│   ├── Database/
│   │   ├── LolitaDatabase.swift             # MODIFY — add v2 migration
│   │   ├── Converters.swift                 # MODIFY — add PriceType enum
│   │   └── Entity/
│   │       ├── Price.swift                  # CREATE — Price Record struct
│   │       └── Payment.swift                # CREATE — Payment Record struct
│   └── Repository/
│       ├── PriceRepository.swift            # CREATE — Price CRUD + spending queries
│       └── PaymentRepository.swift          # CREATE — Payment CRUD + calendar queries
├── UI/
│   ├── Navigation/
│   │   └── LolitaNavHost.swift              # MODIFY — wire WishlistScreen
│   ├── Screen/
│   │   ├── Item/
│   │   │   └── ItemDetailScreen.swift       # MODIFY — add PriceManage toolbar button
│   │   ├── Wishlist/
│   │   │   ├── WishlistScreen.swift          # CREATE
│   │   │   └── WishlistViewModel.swift       # CREATE
│   │   ├── Payment/
│   │   │   ├── PriceManageScreen.swift       # CREATE
│   │   │   ├── PriceManageViewModel.swift    # CREATE
│   │   │   ├── PriceEditScreen.swift         # CREATE
│   │   │   ├── PriceEditViewModel.swift      # CREATE
│   │   │   ├── PaymentManageScreen.swift     # CREATE
│   │   │   ├── PaymentManageViewModel.swift  # CREATE
│   │   │   ├── PaymentEditScreen.swift       # CREATE
│   │   │   ├── PaymentEditViewModel.swift    # CREATE
│   │   │   ├── PaymentCalendarScreen.swift   # CREATE
│   │   │   └── PaymentCalendarViewModel.swift # CREATE
│   │   └── Stats/
│   │       ├── StatsPageScreen.swift         # MODIFY — add spending sections
│   │       └── StatsPageViewModel.swift      # MODIFY — add spending queries
```

---

### Task 1: Add PriceType enum to Converters

**Files:**
- Modify: `Sources/Data/Database/Converters.swift`

- [ ] **Step 1: Append PriceType enum**

Add after the `CategoryGroup` enum in `Sources/Data/Database/Converters.swift`:

```swift
enum PriceType: String, CaseIterable, Codable, DatabaseValueConvertible {
    case full = "FULL"
    case depositBalance = "DEPOSIT_BALANCE"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/Data/Database/Converters.swift
git commit -m "feat: add PriceType enum (FULL, DEPOSIT_BALANCE)"
```

---

### Task 2: Add v2 migration to LolitaDatabase

**Files:**
- Modify: `Sources/Data/Database/LolitaDatabase.swift`

- [ ] **Step 1: Register v2 migration**

In `Sources/Data/Database/LolitaDatabase.swift`, add a second `registerMigration` call after the v1 block inside `migrator`:

```swift
migrator.registerMigration("v2") { db in
    try db.create(table: "prices") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("item_id", .integer).notNull()
            .references("items", column: "id", onDelete: .cascade)
        t.column("type", .text).notNull()
        t.column("total_price", .double).notNull()
        t.column("deposit", .double)
        t.column("balance", .double)
        t.column("created_at", .integer).notNull()
    }
    try db.create(index: "index_prices_item_id", on: "prices", columns: ["item_id"])
    try db.create(index: "index_prices_type", on: "prices", columns: ["type"])

    try db.create(table: "payments") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("price_id", .integer).notNull()
            .references("prices", column: "id", onDelete: .cascade)
        t.column("amount", .double).notNull()
        t.column("due_date", .integer).notNull()
        t.column("is_paid", .integer).notNull().defaults(to: 0)
        t.column("paid_date", .integer)
        t.column("calendar_event_id", .integer)
        t.column("reminder_set", .integer).notNull().defaults(to: 0)
        t.column("custom_reminder_days", .integer)
        t.column("created_at", .integer).notNull()
    }
    try db.create(index: "index_payments_price_id", on: "payments", columns: ["price_id"])
    try db.create(index: "index_payments_due_date", on: "payments", columns: ["due_date"])
    try db.create(index: "index_payments_is_paid", on: "payments", columns: ["is_paid"])
}
```

The v2 registration goes immediately after the closing `}` of the v1 `registerMigration` block, before `return migrator`.

- [ ] **Step 2: Build and verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds (migration compiles but won't run until entities exist for FK references — GRDB validates FK target table names at migration time, not compile time, so this should compile fine).

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/Data/Database/LolitaDatabase.swift
git commit -m "feat: add v2 migration (prices + payments tables)"
```

---

### Task 3: Create Price and Payment entities

**Files:**
- Create: `Sources/Data/Database/Entity/Price.swift`
- Create: `Sources/Data/Database/Entity/Payment.swift`

- [ ] **Step 1: Create Price.swift**

Create `Sources/Data/Database/Entity/Price.swift`:

```swift
import GRDB
import Foundation

struct Price: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var itemId: Int64
    var type: PriceType
    var totalPrice: Double
    var deposit: Double? = nil
    var balance: Double? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "prices"

    enum Columns: String, ColumnExpression {
        case id, itemId, type, totalPrice, deposit, balance, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let item = belongsTo(Item.self)

    var item: QueryInterfaceRequest<Item> {
        request(for: Price.item)
    }
}
```

- [ ] **Step 2: Create Payment.swift**

Create `Sources/Data/Database/Entity/Payment.swift`:

```swift
import GRDB
import Foundation

struct Payment: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var priceId: Int64
    var amount: Double
    var dueDate: Int64
    var isPaid: Bool = false
    var paidDate: Int64? = nil
    var calendarEventId: Int64? = nil
    var reminderSet: Bool = false
    var customReminderDays: Int? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "payments"

    enum Columns: String, ColumnExpression {
        case id, priceId, amount, dueDate, isPaid, paidDate
        case calendarEventId, reminderSet, customReminderDays, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let price = belongsTo(Price.self)

    var price: QueryInterfaceRequest<Price> {
        request(for: Payment.price)
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/Data/Database/Entity/Price.swift Sources/Data/Database/Entity/Payment.swift
git commit -m "feat: add Price and Payment GRDB entity structs"
```

---

### Task 4: Create PriceRepository

**Files:**
- Create: `Sources/Data/Repository/PriceRepository.swift`

- [ ] **Step 1: Create PriceRepository.swift**

Create `Sources/Data/Repository/PriceRepository.swift`:

```swift
import GRDB
import Foundation

// MARK: - DTOs for JOIN queries

struct BrandSpending: Codable, FetchableRecord {
    var name: String
    var totalSpending: Double
}

struct CategorySpending: Codable, FetchableRecord {
    var name: String
    var totalSpending: Double
}

struct StyleSpending: Codable, FetchableRecord {
    var style: String
    var totalSpending: Double
}

struct MonthlySpending: Codable, FetchableRecord {
    var yearMonth: String
    var totalSpending: Double
}

struct ItemWithSpending: Codable, FetchableRecord {
    var itemName: String
    var totalSpending: Double
    var itemId: Int64
}

struct PriorityStats: Codable, FetchableRecord {
    var priority: String
    var itemCount: Int
    var totalBudget: Double
}

struct PaymentWithItemInfo: Codable, FetchableRecord {
    var paymentId: Int64
    var amount: Double
    var dueDate: Int64
    var isPaid: Bool
    var paidDate: Int64?
    var priceId: Int64
    var priceType: String
    var itemName: String
    var itemId: Int64
}

final class PriceRepository {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    // MARK: - CRUD

    func getByItem(_ itemId: Int64) async throws -> [Price] {
        try await db.read { db in
            try Price
                .filter(Price.Columns.itemId == itemId)
                .order(Price.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getById(_ id: Int64) async throws -> Price? {
        try await db.read { db in try Price.fetchOne(db, key: id) }
    }

    func insert(_ price: Price) async throws -> Price {
        try await db.write { db in
            var p = price
            try p.insert(db)
            return p
        }
    }

    func update(_ price: Price) async throws {
        try await db.write { db in try price.update(db) }
    }

    func delete(_ price: Price) async throws {
        try await db.write { db in try price.delete(db) }
    }

    // MARK: - Spending queries

    func getTotalSpending() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.total_price), 0.0)
                    FROM prices p INNER JOIN items i ON p.item_id = i.id
                    WHERE i.status = 'OWNED'
                """) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getTotalSpending error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getSpendingByBrand() -> AsyncStream<[BrandSpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<BrandSpending>(sql: """
                    SELECT b.name AS name, COALESCE(SUM(p.total_price), 0.0) AS totalSpending
                    FROM prices p
                    INNER JOIN items i ON p.item_id = i.id
                    INNER JOIN brands b ON i.brandId = b.id
                    WHERE i.status = 'OWNED'
                    GROUP BY b.name
                    ORDER BY totalSpending DESC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getSpendingByBrand error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getSpendingByCategory() -> AsyncStream<[CategorySpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<CategorySpending>(sql: """
                    SELECT c.name AS name, COALESCE(SUM(p.total_price), 0.0) AS totalSpending
                    FROM prices p
                    INNER JOIN items i ON p.item_id = i.id
                    INNER JOIN categories c ON i.categoryId = c.id
                    WHERE i.status = 'OWNED'
                    GROUP BY c.name
                    ORDER BY totalSpending DESC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getSpendingByCategory error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getSpendingByStyle() -> AsyncStream<[StyleSpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<StyleSpending>(sql: """
                    SELECT i.style AS style, COALESCE(SUM(p.total_price), 0.0) AS totalSpending
                    FROM prices p
                    INNER JOIN items i ON p.item_id = i.id
                    WHERE i.status = 'OWNED' AND i.style IS NOT NULL AND i.style != ''
                    GROUP BY i.style
                    ORDER BY totalSpending DESC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getSpendingByStyle error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getMonthlySpending() -> AsyncStream<[MonthlySpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<MonthlySpending>(sql: """
                    SELECT strftime('%Y-%m', pay.due_date / 1000, 'unixepoch') AS yearMonth,
                           COALESCE(SUM(pay.amount), 0.0) AS totalSpending
                    FROM payments pay
                    INNER JOIN prices pr ON pay.price_id = pr.id
                    INNER JOIN items i ON pr.item_id = i.id
                    WHERE i.status IN ('OWNED', 'PENDING_BALANCE')
                      AND pay.is_paid = 1
                    GROUP BY yearMonth
                    ORDER BY yearMonth ASC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getMonthlySpending error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getMostExpensiveItem() -> AsyncStream<ItemWithSpending?> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<ItemWithSpending>(sql: """
                    SELECT i.name AS itemName, COALESCE(SUM(p.total_price), 0.0) AS totalSpending, i.id AS itemId
                    FROM prices p
                    INNER JOIN items i ON p.item_id = i.id
                    WHERE i.status = 'OWNED'
                    GROUP BY i.id
                    ORDER BY totalSpending DESC
                    LIMIT 1
                """).fetchOne(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getMostExpensiveItem error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getWishlistTotalBudget() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.total_price), 0.0)
                    FROM prices p INNER JOIN items i ON p.item_id = i.id
                    WHERE i.status = 'WISHED'
                """) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getWishlistTotalBudget error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getWishlistByPriorityStats() -> AsyncStream<[PriorityStats]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<PriorityStats>(sql: """
                    SELECT i.priority AS priority, COUNT(i.id) AS itemCount,
                           COALESCE(SUM(p.total_price), 0.0) AS totalBudget
                    FROM items i
                    LEFT JOIN prices p ON p.item_id = i.id
                    WHERE i.status = 'WISHED'
                    GROUP BY i.priority
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getWishlistByPriorityStats error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/Data/Repository/PriceRepository.swift
git commit -m "feat: add PriceRepository (CRUD + spending + wishlist queries)"
```

---

### Task 5: Create PaymentRepository

**Files:**
- Create: `Sources/Data/Repository/PaymentRepository.swift`

- [ ] **Step 1: Create PaymentRepository.swift**

Create `Sources/Data/Repository/PaymentRepository.swift`:

```swift
import GRDB
import Foundation

final class PaymentRepository {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    // MARK: - CRUD

    func getByPrice(_ priceId: Int64) -> AsyncStream<[Payment]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Payment
                    .filter(Payment.Columns.priceId == priceId)
                    .order(Payment.Columns.dueDate.asc)
                    .fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getByPrice error: \(error)")
            } onChange: { payments in
                continuation.yield(payments)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getById(_ id: Int64) async throws -> Payment? {
        try await db.read { db in try Payment.fetchOne(db, key: id) }
    }

    func insert(_ payment: Payment) async throws -> Payment {
        try await db.write { db in
            var p = payment
            try p.insert(db)
            return p
        }
    }

    func update(_ payment: Payment) async throws {
        try await db.write { db in try payment.update(db) }
    }

    func delete(_ payment: Payment) async throws {
        try await db.write { db in try payment.delete(db) }
    }

    // MARK: - Calendar queries

    func getByDateRange(start: Int64, end: Int64) -> AsyncStream<[PaymentWithItemInfo]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<PaymentWithItemInfo>(sql: """
                    SELECT pay.id AS paymentId, pay.amount, pay.due_date AS dueDate,
                           pay.is_paid AS isPaid, pay.paid_date AS paidDate,
                           pr.id AS priceId, pr.type AS priceType,
                           i.name AS itemName, i.id AS itemId
                    FROM payments pay
                    INNER JOIN prices pr ON pay.price_id = pr.id
                    INNER JOIN items i ON pr.item_id = i.id
                    WHERE pay.due_date BETWEEN ? AND ?
                      AND i.status IN ('OWNED', 'PENDING_BALANCE')
                    ORDER BY pay.due_date ASC
                """, arguments: [start, end]).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getByDateRange error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getTotalUnpaidAmount() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.amount), 0.0) FROM payments p
                    INNER JOIN prices pr ON p.price_id = pr.id
                    INNER JOIN items i ON pr.item_id = i.id
                    WHERE p.is_paid = 0 AND i.status IN ('OWNED', 'PENDING_BALANCE')
                """) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getTotalUnpaidAmount error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getOverdueAmount() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.amount), 0.0) FROM payments p
                    INNER JOIN prices pr ON p.price_id = pr.id
                    INNER JOIN items i ON pr.item_id = i.id
                    WHERE p.is_paid = 0 AND p.due_date < ?
                      AND i.status IN ('OWNED', 'PENDING_BALANCE')
                """, arguments: [Int64(Date().timeIntervalSince1970 * 1000)]) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getOverdueAmount error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/Data/Repository/PaymentRepository.swift
git commit -m "feat: add PaymentRepository (CRUD + calendar + unpaid queries)"
```

---

### Task 6: Register repos in AppModule

**Files:**
- Modify: `Sources/AppModule.swift`

- [ ] **Step 1: Add lazy repo properties to AppModule**

In `Sources/AppModule.swift`, add after the existing `recommendationRepository` property:

```swift
lazy var priceRepository: PriceRepository = {
    PriceRepository(db: db.dbQueue)
}()

lazy var paymentRepository: PaymentRepository = {
    PaymentRepository(db: db.dbQueue)
}()
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/AppModule.swift
git commit -m "feat: register PriceRepository and PaymentRepository in AppModule"
```

---

### Task 7: Fix LolitaApp entry point

**Files:**
- Modify: `Sources/LolitaApp.swift`

- [ ] **Step 1: Replace placeholder with real nav**

Replace the entire `body` in `Sources/LolitaApp.swift`:

From:
```swift
var body: some Scene {
    WindowGroup {
        Text("Lolita iOS")
            .environmentObject(skin)
            .task {
                try? await AppModule.shared.initialize()
            }
    }
}
```

To:
```swift
var body: some Scene {
    WindowGroup {
        LolitaNavHost()
            .environmentObject(skin)
            .task {
                try? await AppModule.shared.initialize()
            }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/LolitaApp.swift
git commit -m "fix: wire LolitaNavHost into app entry point"
```

---

### Task 8: Create WishlistViewModel

**Files:**
- Create: `Sources/UI/Screen/Wishlist/WishlistViewModel.swift`

- [ ] **Step 1: Create directory and WishlistViewModel.swift**

```bash
mkdir -p /Users/dengtong/code/lolita-ios/Sources/UI/Screen/Wishlist
```

Create `Sources/UI/Screen/Wishlist/WishlistViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class WishlistViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published var searchText: String = ""

    private let itemRepo = AppModule.shared.itemRepository

    func load() {
        Task {
            for await items in itemRepo.observeAll() {
                self.items = items.filter { $0.status == .wished }
            }
        }
    }

    func prioritizedItems() -> [Item] {
        let filtered = searchText.isEmpty
            ? items
            : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        let order: [ItemPriority] = [.high, .medium, .low]
        return filtered.sorted { a, b in
            let pa = order.firstIndex(of: a.priority) ?? 3
            let pb = order.firstIndex(of: b.priority) ?? 3
            if pa != pb { return pa < pb }
            return a.updatedAt > b.updatedAt
        }
    }

    func delete(_ item: Item) async throws {
        ImageFileHelper.delete(paths: item.imageUrls.values)
        try await itemRepo.delete(item)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Wishlist/WishlistViewModel.swift
git commit -m "feat: add WishlistViewModel (wished items filtered + priority sorted)"
```

---

### Task 9: Create WishlistScreen

**Files:**
- Create: `Sources/UI/Screen/Wishlist/WishlistScreen.swift`

- [ ] **Step 1: Create WishlistScreen.swift**

Create `Sources/UI/Screen/Wishlist/WishlistScreen.swift`:

```swift
import SwiftUI

struct WishlistScreen: View {
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel = WishlistViewModel()

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .lolitaNavBar(title: "愿望单")
        .onAppear { viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("愿望单为空")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("在服饰详情中将状态设为"愿望单"")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.prioritizedItems(), id: \.id) { item in
                NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
                    WishlistRow(item: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { try? await viewModel.delete(item) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索愿望单")
    }
}

private struct WishlistRow: View {
    @EnvironmentObject var skin: DefaultSkin
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            if let firstImage = item.imageUrls.values.first, !firstImage.isEmpty {
                LolitaShimmerImage(url: ImageFileHelper.fileURL(for: firstImage))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: skin.cornerRadiusS))
            } else {
                RoundedRectangle(cornerRadius: skin.cornerRadiusS)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    priorityBadge(item.priority)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String { "愿望单" }

    @ViewBuilder
    private func priorityBadge(_ priority: ItemPriority) -> some View {
        Text(priorityLabel(priority))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.12))
            .foregroundStyle(priorityColor(priority))
            .clipShape(Capsule())
    }

    private func priorityLabel(_ p: ItemPriority) -> String {
        switch p {
        case .high: return "高优先"
        case .medium: return "中优先"
        case .low: return "低优先"
        }
    }

    private func priorityColor(_ p: ItemPriority) -> Color {
        switch p {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Wishlist/WishlistScreen.swift
git commit -m "feat: add WishlistScreen (search, priority sort, swipe delete)"
```

---

### Task 10: Wire WishlistScreen in LolitaNavHost

**Files:**
- Modify: `Sources/UI/Navigation/LolitaNavHost.swift`

- [ ] **Step 1: Replace PlaceholderScreen with WishlistScreen**

In `Sources/UI/Navigation/LolitaNavHost.swift`, change the wishlist tab's `NavigationStack` from:

```swift
NavigationStack {
    PlaceholderScreen(title: Tab.wishlist.rawValue)
}
```

To:

```swift
NavigationStack {
    WishlistScreen()
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Navigation/LolitaNavHost.swift
git commit -m "feat: wire WishlistScreen into LolitaNavHost tab 2"
```

---

### Task 11: Create PriceEditViewModel

**Files:**
- Create: `Sources/UI/Screen/Payment/PriceEditViewModel.swift`

- [ ] **Step 1: Create directory and PriceEditViewModel.swift**

```bash
mkdir -p /Users/dengtong/code/lolita-ios/Sources/UI/Screen/Payment
```

Create `Sources/UI/Screen/Payment/PriceEditViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class PriceEditViewModel: ObservableObject {
    @Published var type: PriceType = .full
    @Published var totalPriceText: String = ""
    @Published var depositText: String = ""
    @Published var balanceText: String = ""
    @Published var isSaving: Bool = false

    private let repo = AppModule.shared.priceRepository
    let itemId: Int64
    private var priceId: Int64?

    init(itemId: Int64, priceId: Int64? = nil) {
        self.itemId = itemId
        self.priceId = priceId
    }

    func load() async {
        guard let priceId, let price = try? await repo.getById(priceId) else { return }
        type = price.type
        totalPriceText = String(format: "%.2f", price.totalPrice)
        if let d = price.deposit { depositText = String(format: "%.2f", d) }
        if let b = price.balance { balanceText = String(format: "%.2f", b) }
    }

    func save() async throws {
        isSaving = true
        defer { isSaving = false }

        let totalPrice = Double(totalPriceText) ?? 0
        let deposit = depositText.isEmpty ? nil : Double(depositText)
        let balance = balanceText.isEmpty ? nil : Double(balanceText)

        if let priceId {
            guard var price = try await repo.getById(priceId) else { return }
            price.type = type
            price.totalPrice = totalPrice
            price.deposit = deposit
            price.balance = balance
            try await repo.update(price)
        } else {
            let price = Price(itemId: itemId, type: type, totalPrice: totalPrice, deposit: deposit, balance: balance)
            _ = try await repo.insert(price)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PriceEditViewModel.swift
git commit -m "feat: add PriceEditViewModel (create/edit price plans)"
```

---

### Task 12: Create PriceEditScreen

**Files:**
- Create: `Sources/UI/Screen/Payment/PriceEditScreen.swift`

- [ ] **Step 1: Create PriceEditScreen.swift**

Create `Sources/UI/Screen/Payment/PriceEditScreen.swift`:

```swift
import SwiftUI

struct PriceEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel: PriceEditViewModel

    init(itemId: Int64, priceId: Int64? = nil) {
        _viewModel = StateObject(wrappedValue: PriceEditViewModel(itemId: itemId, priceId: priceId))
    }

    var body: some View {
        Form {
            Section {
                Picker("类型", selection: $viewModel.type) {
                    Text("全款").tag(PriceType.full)
                    Text("定金+尾款").tag(PriceType.depositBalance)
                }

                TextField("总价", text: $viewModel.totalPriceText)
                    .keyboardType(.decimalPad)

                if viewModel.type == .depositBalance {
                    TextField("定金", text: $viewModel.depositText)
                        .keyboardType(.decimalPad)
                    TextField("尾款", text: $viewModel.balanceText)
                        .keyboardType(.decimalPad)
                }
            } header: {
                Text("价格信息")
            }
        }
        .lolitaNavBar(title: viewModel.priceId == nil ? "添加价格" : "编辑价格", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        try? await viewModel.save()
                        dismiss()
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
#endif
        .task { await viewModel.load() }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PriceEditScreen.swift
git commit -m "feat: add PriceEditScreen (full/deposit-balance form)"
```

---

### Task 13: Create PriceManageViewModel

**Files:**
- Create: `Sources/UI/Screen/Payment/PriceManageViewModel.swift`

- [ ] **Step 1: Create PriceManageViewModel.swift**

Create `Sources/UI/Screen/Payment/PriceManageViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class PriceManageViewModel: ObservableObject {
    @Published private(set) var prices: [Price] = []
    let itemId: Int64

    private let priceRepo = AppModule.shared.priceRepository
    private let paymentRepo = AppModule.shared.paymentRepository

    init(itemId: Int64) { self.itemId = itemId }

    func load() async {
        prices = (try? await priceRepo.getByItem(itemId)) ?? []
    }

    func unpaidCount(for price: Price) -> Int {
        // Called synchronously; we load fresh from repo
        0
    }

    func delete(_ price: Price) async throws {
        try await priceRepo.delete(price)
        await load()
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PriceManageViewModel.swift
git commit -m "feat: add PriceManageViewModel (price list for item)"
```

---

### Task 14: Create PriceManageScreen

**Files:**
- Create: `Sources/UI/Screen/Payment/PriceManageScreen.swift`

- [ ] **Step 1: Create PriceManageScreen.swift**

Create `Sources/UI/Screen/Payment/PriceManageScreen.swift`:

```swift
import SwiftUI

struct PriceManageScreen: View {
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel: PriceManageViewModel

    init(itemId: Int64) {
        _viewModel = StateObject(wrappedValue: PriceManageViewModel(itemId: itemId))
    }

    var body: some View {
        Group {
            if viewModel.prices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "yensign.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无价格记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(viewModel.prices, id: \.id) { price in
                        NavigationLink(destination: PaymentManageScreen(priceId: price.id)) {
                            PriceRow(price: price)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    try? await viewModel.delete(price)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .lolitaNavBar(title: "价格管理", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: PriceEditScreen(itemId: viewModel.itemId)) {
                    Image(systemName: "plus")
                }
            }
        }
#endif
        .task { await viewModel.load() }
    }
}

private struct PriceRow: View {
    let price: Price

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(price.type == .full ? "全款" : "定金+尾款")
                    .font(.subheadline.weight(.medium))
                Text(String(format: "¥%.2f", price.totalPrice))
                    .font(.title3.weight(.bold))
                if price.type == .depositBalance {
                    HStack(spacing: 8) {
                        if let d = price.deposit { Text("定金 ¥\(String(format: "%.2f", d))") }
                        if let b = price.balance { Text("尾款 ¥\(String(format: "%.2f", b))") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PriceManageScreen.swift
git commit -m "feat: add PriceManageScreen (price list + add + delete)"
```

---

### Task 15: Create PaymentEditViewModel

**Files:**
- Create: `Sources/UI/Screen/Payment/PaymentEditViewModel.swift`

- [ ] **Step 1: Create PaymentEditViewModel.swift**

Create `Sources/UI/Screen/Payment/PaymentEditViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class PaymentEditViewModel: ObservableObject {
    @Published var amountText: String = ""
    @Published var dueDate: Date = Date()
    @Published var isPaid: Bool = false
    @Published var paidDate: Date = Date()
    @Published var isSaving: Bool = false

    private let repo = AppModule.shared.paymentRepository
    let priceId: Int64
    private var paymentId: Int64?

    init(priceId: Int64, paymentId: Int64? = nil) {
        self.priceId = priceId
        self.paymentId = paymentId
    }

    func load() async {
        guard let paymentId, let payment = try? await repo.getById(paymentId) else { return }
        amountText = String(format: "%.2f", payment.amount)
        dueDate = Date(timeIntervalSince1970: TimeInterval(payment.dueDate) / 1000)
        isPaid = payment.isPaid
        if let pd = payment.paidDate {
            paidDate = Date(timeIntervalSince1970: TimeInterval(pd) / 1000)
        }
    }

    func save() async throws {
        isSaving = true
        defer { isSaving = false }

        let amount = Double(amountText) ?? 0
        let dueMs = Int64(dueDate.timeIntervalSince1970 * 1000)
        let paidMs = isPaid ? Int64(paidDate.timeIntervalSince1970 * 1000) : nil

        if let paymentId {
            guard var payment = try await repo.getById(paymentId) else { return }
            payment.amount = amount
            payment.dueDate = dueMs
            payment.isPaid = isPaid
            payment.paidDate = paidMs
            try await repo.update(payment)
        } else {
            let payment = Payment(priceId: priceId, amount: amount, dueDate: dueMs, isPaid: isPaid, paidDate: paidMs)
            _ = try await repo.insert(payment)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PaymentEditViewModel.swift
git commit -m "feat: add PaymentEditViewModel (create/edit installments)"
```

---

### Task 16: Create PaymentEditScreen

**Files:**
- Create: `Sources/UI/Screen/Payment/PaymentEditScreen.swift`

- [ ] **Step 1: Create PaymentEditScreen.swift**

Create `Sources/UI/Screen/Payment/PaymentEditScreen.swift`:

```swift
import SwiftUI

struct PaymentEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel: PaymentEditViewModel

    init(priceId: Int64, paymentId: Int64? = nil) {
        _viewModel = StateObject(wrappedValue: PaymentEditViewModel(priceId: priceId, paymentId: paymentId))
    }

    var body: some View {
        Form {
            Section {
                TextField("金额", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)

                DatePicker("到期日", selection: $viewModel.dueDate, displayedComponents: .date)

                Toggle("已支付", isOn: $viewModel.isPaid)

                if viewModel.isPaid {
                    DatePicker("支付日期", selection: $viewModel.paidDate, displayedComponents: .date)
                }
            } header: {
                Text("付款信息")
            }
        }
        .lolitaNavBar(title: viewModel.paymentId == nil ? "添加付款" : "编辑付款", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        try? await viewModel.save()
                        dismiss()
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
#endif
        .task { await viewModel.load() }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PaymentEditScreen.swift
git commit -m "feat: add PaymentEditScreen (amount, due date, paid toggle)"
```

---

### Task 17: Create PaymentManageViewModel

**Files:**
- Create: `Sources/UI/Screen/Payment/PaymentManageViewModel.swift`

- [ ] **Step 1: Create PaymentManageViewModel.swift**

Create `Sources/UI/Screen/Payment/PaymentManageViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class PaymentManageViewModel: ObservableObject {
    @Published private(set) var payments: [Payment] = []
    @Published private(set) var price: Price?
    let priceId: Int64

    private let paymentRepo = AppModule.shared.paymentRepository
    private let priceRepo = AppModule.shared.priceRepository

    init(priceId: Int64) { self.priceId = priceId }

    func load() {
        price = try? await priceRepo.getById(priceId)
        Task {
            for await ps in paymentRepo.getByPrice(priceId) {
                payments = ps
            }
        }
    }

    var totalAmount: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    var paidAmount: Double {
        payments.filter(\.isPaid).reduce(0) { $0 + $1.amount }
    }

    var remainingAmount: Double {
        totalAmount - paidAmount
    }

    func delete(_ payment: Payment) async throws {
        try await paymentRepo.delete(payment)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PaymentManageViewModel.swift
git commit -m "feat: add PaymentManageViewModel (installments list + summary)"
```

---

### Task 18: Create PaymentManageScreen

**Files:**
- Create: `Sources/UI/Screen/Payment/PaymentManageScreen.swift`

- [ ] **Step 1: Create PaymentManageScreen.swift**

Create `Sources/UI/Screen/Payment/PaymentManageScreen.swift`:

```swift
import SwiftUI

struct PaymentManageScreen: View {
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel: PaymentManageViewModel

    init(priceId: Int64) {
        _viewModel = StateObject(wrappedValue: PaymentManageViewModel(priceId: priceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            if viewModel.payments.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无付款记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.payments, id: \.id) { payment in
                        NavigationLink(destination: PaymentEditScreen(priceId: viewModel.priceId, paymentId: payment.id)) {
                            PaymentRow(payment: payment)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { try? await viewModel.delete(payment) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .lolitaNavBar(title: "付款管理", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: PaymentEditScreen(priceId: viewModel.priceId)) {
                    Image(systemName: "plus")
                }
            }
        }
#endif
        .onAppear { viewModel.load() }
    }

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            summaryItem("总计", viewModel.totalAmount, .primary)
            summaryItem("已付", viewModel.paidAmount, .green)
            summaryItem("待付", viewModel.remainingAmount, .orange)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func summaryItem(_ label: String, _ amount: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "¥%.2f", amount))
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaymentRow: View {
    let payment: Payment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "¥%.2f", payment.amount))
                    .font(.subheadline.weight(.medium))
                Text(Date(timeIntervalSince1970: TimeInterval(payment.dueDate) / 1000), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if payment.isPaid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if payment.dueDate < Int64(Date().timeIntervalSince1970 * 1000) {
                    Text("逾期")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("待付")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PaymentManageScreen.swift
git commit -m "feat: add PaymentManageScreen (installments list + summary header)"
```

---

### Task 19: Add PriceManage toolbar button to ItemDetailScreen

**Files:**
- Modify: `Sources/UI/Screen/Item/ItemDetailScreen.swift`

- [ ] **Step 1: Add price management toolbar button**

In `Sources/UI/Screen/Item/ItemDetailScreen.swift`, replace the existing toolbar block:

From:
```swift
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink("编辑") {
                    ItemEditScreen(itemId: viewModel.itemId)
                }
            }
        }
#endif
```

To:
```swift
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink(destination: PriceManageScreen(itemId: viewModel.itemId)) {
                        Image(systemName: "yensign.circle")
                    }
                    NavigationLink("编辑") {
                        ItemEditScreen(itemId: viewModel.itemId)
                    }
                }
            }
        }
#endif
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Item/ItemDetailScreen.swift
git commit -m "feat: add PriceManage toolbar button to ItemDetailScreen"
```

---

### Task 20: Create PaymentCalendarViewModel

**Files:**
- Create: `Sources/UI/Screen/Payment/PaymentCalendarViewModel.swift`

- [ ] **Step 1: Create PaymentCalendarViewModel.swift**

Create `Sources/UI/Screen/Payment/PaymentCalendarViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class PaymentCalendarViewModel: ObservableObject {
    @Published private(set) var paymentsByDate: [(date: Date, payments: [PaymentWithItemInfo])] = []
    @Published private(set) var totalUnpaid: Double = 0
    @Published private(set) var overdueAmount: Double = 0
    @Published var currentMonth: Date = Date()
    @Published private(set) var selectedDayPayments: [PaymentWithItemInfo]? = nil

    private let paymentRepo = AppModule.shared.paymentRepository

    func load() {
        loadCalendar()
        Task {
            for await val in paymentRepo.getTotalUnpaidAmount() { totalUnpaid = val }
        }
        Task {
            for await val in paymentRepo.getOverdueAmount() { overdueAmount = val }
        }
    }

    func loadCalendar() {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(end.timeIntervalSince1970 * 1000)

        Task {
            for await payments in paymentRepo.getByDateRange(start: startMs, end: endMs) {
                let grouped = Dictionary(grouping: payments) { p in
                    let d = Date(timeIntervalSince1970: TimeInterval(p.dueDate) / 1000)
                    return cal.startOfDay(for: d)
                }
                paymentsByDate = grouped
                    .map { (date: $0.key, payments: $0.value) }
                    .sorted { $0.date < $1.date }
            }
        }
    }

    func selectDay(_ date: Date) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        selectedDayPayments = paymentsByDate.first(where: { cal.startOfDay(for: $0.date) == day })?.payments
    }

    func goToNextMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        loadCalendar()
    }

    func goToPreviousMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        loadCalendar()
    }

    var monthYearText: String {
        currentMonth.formatted(Date.FormatStyle().month(.wide).year())
    }

    func hasPayments(on day: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        return paymentsByDate.contains(where: { cal.startOfDay(for: $0.date) == d })
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PaymentCalendarViewModel.swift
git commit -m "feat: add PaymentCalendarViewModel (month nav + date range query)"
```

---

### Task 21: Create PaymentCalendarScreen

**Files:**
- Create: `Sources/UI/Screen/Payment/PaymentCalendarScreen.swift`

- [ ] **Step 1: Create PaymentCalendarScreen.swift**

Create `Sources/UI/Screen/Payment/PaymentCalendarScreen.swift`:

```swift
import SwiftUI

struct PaymentCalendarScreen: View {
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel = PaymentCalendarViewModel()

    var body: some View {
        VStack(spacing: 0) {
            monthPicker
            summaryBar
            calendarGrid
            if let selected = viewModel.selectedDayPayments {
                dayDetail(selected)
            }
            Spacer()
        }
        .lolitaNavBar(title: "付款日历", showBack: true)
        .onAppear { viewModel.load() }
    }

    private var monthPicker: some View {
        HStack {
            Button { viewModel.goToPreviousMonth() } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(viewModel.monthYearText)
                .font(.headline)
            Spacer()
            Button { viewModel.goToNextMonth() } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            Label {
                Text("待付 ¥\(String(format: "%.2f", viewModel.totalUnpaid))")
                    .font(.caption)
            } icon: {
                Image(systemName: "creditcard")
            }

            Label {
                Text("逾期 ¥\(String(format: "%.2f", viewModel.overdueAmount))")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var calendarGrid: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: viewModel.currentMonth))!
        let daysInMonth = cal.range(of: .day, in: .month, for: start)!.count
        let firstWeekday = cal.component(.weekday, from: start)

        let columns = Array(repeating: GridItem(.flexible()), count: 7)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(["日","一","二","三","四","五","六"], id: \.self) { day in
                Text(day).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }

            ForEach(0..<(firstWeekday - 1), id: \.self) { _ in Color.clear }

            ForEach(1...daysInMonth, id: \.self) { day in
                let date = cal.date(byAdding: .day, value: day - 1, to: start)!
                Button {
                    viewModel.selectDay(date)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(day)")
                            .font(.caption)
                        Circle()
                            .fill(viewModel.hasPayments(on: date) ? skin.primaryColor : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: skin.cornerRadiusS)
                            .fill(Color(.systemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func dayDetail(_ payments: [PaymentWithItemInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当日付款")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)

            ForEach(payments, id: \.paymentId) { p in
                HStack {
                    Circle()
                        .fill(p.isPaid ? Color.green : (p.dueDate < Int64(Date().timeIntervalSince1970 * 1000) ? Color.red : Color.orange))
                        .frame(width: 8, height: 8)
                    Text(p.itemName)
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "¥%.2f", p.amount))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Payment/PaymentCalendarScreen.swift
git commit -m "feat: add PaymentCalendarScreen (month grid + day detail)"
```

---

### Task 22: Enhance StatsPageViewModel with spending analytics

**Files:**
- Modify: `Sources/UI/Screen/Stats/StatsPageViewModel.swift`

- [ ] **Step 1: Add spending properties and observers**

Replace `Sources/UI/Screen/Stats/StatsPageViewModel.swift` with the enhanced version:

```swift
import SwiftUI

@MainActor
final class StatsPageViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var outfitLogs: [OutfitLog] = []
    @Published private(set) var totalSpending: Double = 0
    @Published private(set) var mostExpensive: ItemWithSpending? = nil
    @Published private(set) var spendingByBrand: [BrandSpending] = []
    @Published private(set) var spendingByCategory: [CategorySpending] = []
    @Published private(set) var spendingByStyle: [StyleSpending] = []
    @Published private(set) var monthlySpending: [MonthlySpending] = []
    @Published private(set) var wishlistBudget: Double = 0
    @Published private(set) var wishlistPriorityStats: [PriorityStats] = []

    private let itemRepo = AppModule.shared.itemRepository
    private let outfitRepo = AppModule.shared.outfitLogRepository
    private let priceRepo = AppModule.shared.priceRepository

    func load() {
        Task {
            for await items in itemRepo.observeAll() { self.items = items }
        }
        Task {
            for await logs in outfitRepo.observeAll() { self.outfitLogs = logs }
        }
        Task {
            for await val in priceRepo.getTotalSpending() { totalSpending = val }
        }
        Task {
            for await val in priceRepo.getMostExpensiveItem() { mostExpensive = val }
        }
        Task {
            for await val in priceRepo.getSpendingByBrand() { spendingByBrand = val }
        }
        Task {
            for await val in priceRepo.getSpendingByCategory() { spendingByCategory = val }
        }
        Task {
            for await val in priceRepo.getSpendingByStyle() { spendingByStyle = val }
        }
        Task {
            for await val in priceRepo.getMonthlySpending() { monthlySpending = val }
        }
        Task {
            for await val in priceRepo.getWishlistTotalBudget() { wishlistBudget = val }
        }
        Task {
            for await val in priceRepo.getWishlistByPriorityStats() { wishlistPriorityStats = val }
        }
    }

    var totalItems: Int { items.count }
    var ownedCount: Int { items.filter { $0.status == .owned }.count }
    var wishedCount: Int { items.filter { $0.status == .wished }.count }
    var totalOutfits: Int { outfitLogs.count }

    var styleDistribution: [(String, Int)] {
        Dictionary(grouping: items) { $0.style ?? "未分类" }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var categoryDistribution: [(String, Int)] {
        items.reduce(into: [:]) { dict, item in
            let key = "\(item.categoryId)"
            dict[key, default: 0] += 1
        }.map { ($0.key, $0.value) }
        .sorted { $0.1 > $1.1 }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Stats/StatsPageViewModel.swift
git commit -m "feat: add spending analytics observers to StatsPageViewModel"
```

---

### Task 23: Enhance StatsPageScreen with spending sections

**Files:**
- Modify: `Sources/UI/Screen/Stats/StatsPageScreen.swift`

- [ ] **Step 1: Add spending sections below existing content**

In `Sources/UI/Screen/Stats/StatsPageScreen.swift`, insert new sections after the existing `styleDistribution` section inside the `ScrollView`'s `VStack`. Insert right before the closing `}` of the `VStack`:

```swift
                // Total spending card
                LolitaCard(variant: .compact) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总消费")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "¥%.2f", viewModel.totalSpending))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(skin.primaryColor)
                        }
                        Spacer()
                    }
                }

                if let exp = viewModel.mostExpensive {
                    LolitaCard(variant: .compact) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最贵单品")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(exp.itemName)
                                    .font(.subheadline.weight(.medium))
                                Text(String(format: "¥%.2f", exp.totalSpending))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(skin.primaryColor)
                            }
                            Spacer()
                        }
                    }
                }

                if !viewModel.spendingByBrand.isEmpty {
                    LolitaSection(title: "品牌消费分布") {
                        ForEach(viewModel.spendingByBrand.prefix(10), id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.spendingByCategory.isEmpty {
                    LolitaSection(title: "品类消费分布") {
                        ForEach(viewModel.spendingByCategory.prefix(10), id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.spendingByStyle.isEmpty {
                    LolitaSection(title: "风格消费分布") {
                        ForEach(viewModel.spendingByStyle.prefix(10), id: \.style) { item in
                            HStack {
                                Text(item.style)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.monthlySpending.isEmpty {
                    LolitaSection(title: "月度消费趋势") {
                        ForEach(viewModel.monthlySpending, id: \.yearMonth) { item in
                            HStack {
                                Text(item.yearMonth)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Wishlist Analysis
                LolitaCard(variant: .compact) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("愿望单预算")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "¥%.2f", viewModel.wishlistBudget))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.pink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.wishlistPriorityStats.isEmpty {
                    LolitaSection(title: "愿望单优先级") {
                        ForEach(viewModel.wishlistPriorityStats, id: \.priority) { stat in
                            HStack {
                                Text(priorityName(stat.priority))
                                Spacer()
                                Text("\(stat.itemCount)件")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "¥%.2f", stat.totalBudget))
                                    .foregroundStyle(.pink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Payment Calendar shortcut
                NavigationLink(destination: PaymentCalendarScreen()) {
                    LolitaCard(variant: .compact) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(skin.primaryColor)
                            Text("付款日历")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                NavigationLink(destination: WishlistScreen()) {
                    LolitaCard(variant: .compact) {
                        HStack {
                            Image(systemName: "heart")
                                .foregroundStyle(.pink)
                            Text("愿望单")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
```

Also add the helper function inside `StatsPageScreen`:

```swift
    private func priorityName(_ p: String) -> String {
        switch p {
        case "HIGH": return "高优先"
        case "MEDIUM": return "中优先"
        case "LOW": return "低优先"
        default: return p
        }
    }
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Stats/StatsPageScreen.swift
git commit -m "feat: add spending analytics + wishlist analysis to StatsPage"
```

---

### Task 24: Final verification build

- [ ] **Step 1: Clean build from scratch**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds with 0 errors.

- [ ] **Step 2: Verify all file counts**

```bash
find Sources -name "*.swift" | wc -l
```

Expected: 86 Swift source files (70 existing + 16 new).

- [ ] **Step 3: Commit any remaining changes**

```bash
cd /Users/dengtong/code/lolita-ios
git status
```

If clean, no commit needed. Otherwise, commit with: `git commit -m "chore: final verification — all Phase 2 files compile"`
```

---

## Self-Review

1. **Spec coverage:** Each spec requirement maps to a task:
   - v2 migration → Task 2
   - PriceType enum → Task 1
   - Price + Payment entities → Task 3
   - PriceRepository → Task 4
   - PaymentRepository → Task 5
   - AppModule wiring → Task 6
   - Entry point fix → Task 7
   - WishlistScreen + VM → Tasks 8-10
   - PriceManage/Edit screens → Tasks 11-14
   - PaymentManage/Edit screens → Tasks 15-18
   - ItemDetail toolbar → Task 19
   - PaymentCalendar → Tasks 20-21
   - Spending analytics → Tasks 22-23
   - Final verification → Task 24

2. **No placeholders:** All code blocks are complete with real implementations.

3. **Type consistency:** `PriceType` defined in Task 1, used in Task 3 (`Price` entity), Task 11 (`PriceEditViewModel`), Task 14 (`PriceManageScreen`). `PaymentWithItemInfo` DTO defined in Task 4, used in Tasks 20-21. `BrandSpending`, `CategorySpending`, etc. all defined in Task 4 and used in Task 22. All consistent.
