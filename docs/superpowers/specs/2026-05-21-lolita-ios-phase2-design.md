# Lolita iOS Phase 2 Design Spec

2026-05-21

## Overview

Phase 2 adds wishlist functionality, full payment tracking (prices + installments), payment calendar, and spending analytics to the iOS app. Also fixes the `LolitaApp` entry point which currently shows a placeholder `Text` instead of the real navigation.

**Target:** 1:1 feature parity with Android payment system (data-only — no iOS notification/calendar integration this round). Continue SwiftUI + GRDB + MVVM pattern from Phase 1.

## Database (v2 Migration)

Incremental v2 migration added to the existing chain. Two new tables:

### prices

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | autoIncrement |
| item_id | INTEGER NOT NULL | FK → items.id, CASCADE delete |
| type | TEXT NOT NULL | `FULL` or `DEPOSIT_BALANCE` |
| total_price | REAL NOT NULL | total cost |
| deposit | REAL | deposit amount (for DEPOSIT_BALANCE) |
| balance | REAL | balance amount (for DEPOSIT_BALANCE) |
| created_at | INTEGER NOT NULL | timestamp ms |

Indexes: `item_id`, `type`

### payments

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | autoIncrement |
| price_id | INTEGER NOT NULL | FK → prices.id, CASCADE delete |
| amount | REAL NOT NULL | installment amount |
| due_date | INTEGER NOT NULL | timestamp ms |
| is_paid | INTEGER NOT NULL | 0/1, default 0 |
| paid_date | INTEGER | when marked paid |
| calendar_event_id | INTEGER | reserved for future calendar integration |
| reminder_set | INTEGER NOT NULL | 0/1, default 0 |
| custom_reminder_days | INTEGER | reserved for future notifications |
| created_at | INTEGER NOT NULL | timestamp ms |

Indexes: `price_id`, `due_date`, `is_paid`

### New Enum

`PriceType`: `.full`, `.depositBalance` — stored as TEXT in DB, implements `DatabaseValueConvertible`.

## New Entities

- **Price** — `Codable, FetchableRecord, PersistableRecord` with `belongsTo(Item.self)`
- **Payment** — `Codable, FetchableRecord, PersistableRecord` with `belongsTo(Price.self)`
- **DTOs** (plain structs for JOIN query results): `PaymentWithItemInfo`, `BrandSpending`, `CategorySpending`, `StyleSpending`, `MonthlySpending`, `ItemWithSpending`, `PriorityStats`, `PriceWithPayments`

## New Repositories

**PriceRepository** (`Data/Repository/PriceRepository.swift`):
- CRUD: `getByItem(itemId)`, `insert`, `update`, `delete`
- Spending: `getTotalSpending()`, `getSpendingByBrand()`, `getSpendingByCategory()`, `getSpendingByStyle()`, `getSpendingBySeason()`
- Trends: `getMonthlySpending()`, `getMostExpensiveItem()`, `getItemsByPurchaseMonth(yearMonth)`
- Wishlist: `getWishlistTotalBudget()`, `getWishlistByPriorityStats()`

**PaymentRepository** (`Data/Repository/PaymentRepository.swift`):
- CRUD: `getByPrice(priceId)`, `getById`, `insert`, `update`, `delete`
- Calendar: `getByDateRange(start, end)`, `getMonthUnpaidTotal(month)`, `getTotalUnpaidAmount()`, `getOverdueAmount(now)`
- Reminders: `getPendingReminders()` (future notification use)

## Entry Point Fix

Change `Sources/LolitaApp.swift`:
- Replace `Text("Lolita iOS")` with `LolitaNavHost()`
- Inject `DefaultSkin` as `@EnvironmentObject`
- Keep the `AppModule.shared.initialize()` async task

## Wishlist Tab

Replace `PlaceholderScreen` in `LolitaNavHost` tab 2 with `WishlistScreen`.

**WishlistViewModel:**
- Observes items via `ItemRepository.observeAll()`, filters to `.wished` status
- Sorts by priority (HIGH → MEDIUM → LOW), then by updatedAt desc
- `delete(item)` method with swipe-to-delete support

**WishlistScreen:**
- Search bar at top (local filtering by name)
- List of wished items, each row showing thumbnail, name, priority badge, status text
- Swipe-to-delete with confirmation
- Tap navigates to existing `ItemDetailScreen`

## Payment Screens

All follow existing MVVM + Form pattern (see `OutfitLogEditScreen`).

**PriceManageScreen** — lists price plans for an item:
- Accessible from `ItemDetailScreen` via toolbar button
- Shows type badge (FULL / DEPOSIT_BALANCE), total price, paid/unpaid breakdown
- Add button → `PriceEditScreen`
- Tap row → `PaymentManageScreen`

**PriceEditScreen** — create/edit price plan:
- Picker for type (FULL / DEPOSIT_BALANCE)
- TextField for total price (decimal input)
- Conditional deposit + balance fields (shown only for DEPOSIT_BALANCE)
- Save → dismiss

**PaymentManageScreen** — installments for a price plan:
- List of payments with due date, amount, paid status
- Summary header: total, paid, remaining
- Add button → `PaymentEditScreen`
- Tap row → `PaymentEditScreen`

**PaymentEditScreen** — create/edit installment:
- TextField for amount
- DatePicker for due date
- Toggle for isPaid
- Conditional DatePicker for paidDate (when isPaid is true)
- Save → dismiss

## Payment Calendar

**PaymentCalendarScreen:**
- Month picker header (previous/next month, current month label)
- Summary bar: total unpaid amount, overdue amount
- Calendar grid showing days of the month
- Each day cell shows a dot if payments are due
- Tap a day → bottom sheet or inline list of that day's payments
- Uses `PaymentRepository.getByDateRange()` + `getOverdueAmount()`

## Spending Analytics

Enhance `StatsPageScreen` and `StatsPageViewModel` with new sections below existing cards:

1. **Total Spending** — single large card showing sum of all owned item prices
2. **Most Expensive Item** — card showing item name + price
3. **Spending Distribution** — reuse existing style distribution pattern; add brand, category, style tabs
4. **Monthly Trend** — horizontal bar or simple list of year-month → total paid
5. **Wishlist Analysis** — total budget, satisfaction rate (owned/wished), by-priority breakdown

## Navigation Wiring

```
LolitaNavHost
├── Tab 1: 服饰 → ItemListScreen → ItemDetailScreen → PriceManageScreen → PriceEditScreen
│                                                                    → PaymentManageScreen → PaymentEditScreen
├── Tab 2: 愿望单 → WishlistScreen → ItemDetailScreen (existing)
├── Tab 3: 穿搭 → CoordinateListScreen (existing)
├── Tab 4: 统计 → StatsPageScreen (enhanced) → PaymentCalendarScreen
└── Tab 5: 设置 → SettingsScreen (existing)
```

## Implementation Order (Bottom-up)

1. Database v2 migration + PriceType enum
2. Price, Payment entities + DTOs
3. PriceRepository + PaymentRepository
4. Fix LolitaApp entry point
5. WishlistScreen + WishlistViewModel
6. PriceManageScreen + PriceEditScreen + ViewModels
7. PaymentManageScreen + PaymentEditScreen + ViewModels
8. PaymentCalendarScreen + ViewModel
9. Enhanced StatsPageScreen (spending analytics)
10. Final navigation wiring + toolbar buttons

## Out of Scope

- iOS notification scheduling (UNUserNotificationCenter)
- iOS calendar integration (EventKit)
- Taobao order import
- Backup/restore
- Additional skins (Gothic, Chinese, Classic, Navy, Country, Victorian)
- Home screen widget
- Shared library sync
- Skin animation system
