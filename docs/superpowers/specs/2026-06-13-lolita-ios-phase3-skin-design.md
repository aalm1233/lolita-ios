# Lolita iOS Phase 3 Design Spec — 皮肤系统 (Skin System)

2026-06-13

## Overview

Phase 3 ports the 6 remaining skins from Android (Gothic, Chinese, Classic, Navy, Country, Victorian) to the iOS app, completing full visual parity with the Android skin system. This phase covers **colors, fonts, and shapes only** — custom icons and animations are deferred to follow-up phases.

**Target:** 7-skin system with runtime switching, matching Android's color/font/shape tokens. Continue SwiftUI + MVVM + `@EnvironmentObject` pattern from Phase 1-2.

**Out of scope this phase:**
- Custom icons (45+ per skin) — Phase 3b
- Animations (entrance, navigation, ripple, particles) — Phase 3c
- Haze blur on nav bar (no SwiftUI-native Haze equivalent yet)

## Architecture

```
SkinProtocol (protocol)          ← extended with ~15 new tokens
    ├── DefaultSkin              ← existing, renamed SweetSkin
    ├── GothicSkin               ← NEW
    ├── ChineseSkin              ← NEW
    ├── ClassicSkin              ← NEW
    ├── NavySkin                 ← NEW
    ├── CountrySkin              ← NEW
    └── VictorianSkin            ← NEW

SkinManager (ObservableObject)   ← NEW, holds current skin
    ├── @Published skin: any SkinProtocol
    ├── switch(to:) → updates skin + persists preference
    └── customFont: Font?        ← computed from current skin
```

**Data flow:** `SkinManager (ObservableObject) → @EnvironmentObject → Views/Components`

### SkinManager

```swift
final class SkinManager: ObservableObject {
    @Published var current: any SkinProtocol
    @Published var currentSkinType: SkinType = .default
    private let preferences: AppPreferences

    func switch(to type: SkinType) {
        current = SkinManager.create(type)
        currentSkinType = type
        preferences.skinType = type.rawValue
    }

    var customFont: Font? {
        guard let name = current.fontName else { return nil }
        return Font.custom(name, size: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }
}
```

- Persists `skinType` to `AppPreferences` (UserDefaults-backed String)
- Initializes from stored preference on launch, defaults to `.default`
- `SkinType` enum: `default, gothic, chinese, classic, navy, country, victorian`
- `currentSkinType` is `@Published` so `ThemeSelectScreen` can observe it for checkmark display

## SkinProtocol Extension

New tokens (all with protocol extension defaults for backward compatibility):

### Font
| Token | Type | Default |
|-------|------|---------|
| `fontName` | `String?` | `nil` (system default) |
| `fontDisplayName` | `String` | `"系统默认"` |

### Image Frame
| Token | Type | Default |
|-------|------|---------|
| `imageFrameElevation` | `CGFloat` | `2` |
| `imageFrameBorderStroke` | `(Color, CGFloat)?` | `nil` |
| `imageFrameBorderStrokeDark` | `(Color, CGFloat)?` | `nil` |
| `imageFramePadding` | `CGFloat` | `0` |

### Dark Mode Borders
| Token | Type | Default |
|-------|------|---------|
| `cardBorderStrokeDark` | `(Color, CGFloat)?` | `nil` |
| `sectionDividerColorDark` | `Color` | `sectionDividerColor` |
| `sectionAccentColorDark` | `Color` | `sectionAccentColor` |

### Shapes
| Token | Type | Default |
|-------|------|---------|
| `buttonCornerRadius` | `CGFloat` | `cornerRadiusM` |

### Blur
| Token | Type | Default |
|-------|------|---------|
| `navBarBlurEnabled` | `Bool` | `false` |
| `dialogBlurEnabled` | `Bool` | `false` |

### Tab Bar
| Token | Type | Default |
|-------|------|---------|
| `tabBarBackgroundColor` | `Color` | `cardColor` |
| `tabBarBackgroundColorDark` | `Color` | `cardColorDark` |

## Skin Specifications

### DEFAULT — 甜美粉 (Sweet Pink)

Existing `DefaultSkin` renamed to `SweetSkin`. All values unchanged from current code.

| Token | Value |
|-------|-------|
| Primary | `#FF69B4` |
| Secondary | `#E6E6FA` |
| Background | `#FFF0F5` |
| Corner M | 16pt |
| Font | System default |
| Decoration | ✿ at 70% |
| Card border | none |

### GOTHIC — 哥特暗黑

| Token | Value |
|-------|-------|
| Primary | `#4A0E4E` (deep purple) |
| Secondary | `#8B0000` (blood red) |
| Background | `#F5F0F5` |
| Primary Dark | `#BB86FC` |
| Background Dark | `#1A1A2E` |
| Card Dark | `#2D2D44` |
| Corner S/M/L | 4 / 8 / 12pt |
| Button Corner | 6pt |
| Font | Cinzel Regular |
| Decoration | ✝ at 50% |
| Card elevation | 2 |
| Section accent width | 2 |
| Card gap | 16 |
| Card inner padding | 14 |

### CHINESE — 中华风韵

| Token | Value |
|-------|-------|
| Primary | `#C41E3A` (vermillion) |
| Secondary | `#DAA520` (goldenrod) |
| Background | `#FFF8F0` |
| Primary Dark | `#FF6B6B` |
| Background Dark | `#1A1410` |
| Card Dark | `#2D2520` |
| Corner S/M/L | 2 / 4 / 8pt |
| Button Corner | 4pt |
| Font | Noto Serif SC Regular |
| Decoration | ☁ at 60% |
| Card elevation | 2 |
| Section accent width | 3 |
| Card gap | 12 |
| Card inner padding | 16 |

### CLASSIC — 经典优雅

| Token | Value |
|-------|-------|
| Primary | `#722F37` (wine/burgundy) |
| Secondary | `#8B4513` (saddle brown) |
| Background | `#FAF5F0` |
| Primary Dark | `#C49098` |
| Background Dark | `#1A1515` |
| Card Dark | `#2D2525` |
| Corner S/M/L | 6 / 12 / 16pt |
| Button Corner | 8pt |
| Font | Playfair Display Regular |
| Decoration | ♠ at 50% |
| Card elevation | 2 |
| Section accent width | 3 |
| Card gap | 16 |
| Card inner padding | 16 |

### NAVY — 清风水手

| Token | Value |
|-------|-------|
| Primary | `#4A90D9` (sky blue) |
| Secondary | `#DAA520` (gold) |
| Background | `#F0F8FF` (Alice Blue) |
| Primary Dark | `#7AB8F5` |
| Background Dark | `#0D1B2A` |
| Card Dark | `#1B2D44` |
| Corner S/M/L | 7 / 14 / 20pt |
| Button Corner | 14pt |
| Font | Pacifico Regular |
| Decoration | ⚓ at 60% |
| Card elevation | 1.5 |
| Section accent width | 3 |
| Card gap | 18 |
| Card inner padding | 16 |

### COUNTRY — 田园牧歌

| Token | Value |
|-------|-------|
| Primary | `#7C9A69` (sage green) |
| Secondary | `#C56759` (berry) |
| Background | `#F9F4E8` (cream) |
| Primary Dark | `#A8C99A` |
| Background Dark | `#1F261C` |
| Card Dark | `#2D3529` |
| Corner S/M/L | 10 / 20 / 28pt |
| Button Corner | 18pt |
| Font | Cormorant Garamond Regular |
| Decoration | ✿ at 70% |
| Card elevation | 1 |
| Section accent width | 3 |
| Card gap | 14 |
| Card inner padding | 18 |

### VICTORIAN — 维多利亚

| Token | Value |
|-------|-------|
| Primary | `#7B1E3A` (burgundy) |
| Secondary | `#B8860B` (dark gold) |
| Background | `#FFF8F0` (ivory) |
| Primary Dark | `#C49098` |
| Background Dark | `#1A1210` |
| Card Dark | `#2C1E18` |
| Corner S/M/L | 6 / 12 / 16pt |
| Button Corner | 8pt |
| Font | Cormorant Garamond Regular |
| Decoration | ⚜ at 50% |
| Card elevation | 3 |
| Card border | gold 1pt |
| Card border dark | gold 0.5pt |
| Section accent width | 3 |
| Card gap | 20 |
| Card inner padding | 16 |
| Image frame border | gold 1pt |

## Component Changes

### 1. LolitaCard (MODIFY)

- Add dark mode border resolution: use `cardBorderStrokeDark` when `colorScheme == .dark` and the token is non-nil
- No other changes — existing behavior preserved

### 2. ImageFrame (CREATE)

New component, porting Android's image frame concept:

```swift
struct ImageFrame<Content: View>: View {
    @EnvironmentObject var skin: SkinManager  // via SkinManager
    @Environment(\.colorScheme) var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(skin.current.imageFramePadding)
            .background(RoundedRectangle(...).fill(...))
            .overlay(border stroke if present)
            .shadow(...)
    }
}
```

Usage: wrap existing `LolitaShimmerImage` calls or plain `Image` views.

### 3. LolitaNavigationBar (MODIFY)

- Read `navBarBlurEnabled` for conditional blur effect

### 4. LolitaSection (MODIFY)

- Read `sectionDividerColorDark` / `sectionAccentColorDark` for dark mode adaptation
- Existing light mode behavior unchanged

### 5. Global Font (NEW in SkinManager)

- `SkinManager` exposes `var customFont: Font?`
- Views opt-in: `.font(skinManager.customFont ?? .body)`
- No forced font change — each view decides whether to use the skin font

## Entry Point Changes

### LolitaApp.swift (MODIFY)

```swift
@main
struct LolitaApp: App {
    @StateObject private var skinManager = SkinManager()

    var body: some Scene {
        WindowGroup {
            LolitaNavHost()
                .environmentObject(skinManager)
                // ...
        }
    }
}
```

### All Consumer Files (MODIFY — ~20 files)

Change `@EnvironmentObject var skin: DefaultSkin` → `@EnvironmentObject var skinManager: SkinManager`

Access pattern: `skinManager.current.primaryColor` instead of `skin.primaryColor`

**Decision: Direct replacement.** Change all `@EnvironmentObject var skin: DefaultSkin` to `@EnvironmentObject var skinManager: SkinManager`. Reference tokens via `skinManager.current.xxx`. This is the cleanest long-term approach — `SkinManager` is the single source of truth, and `current` always gives the active skin's values. No forwarding boilerplate needed on `SkinManager`.

## ThemeSelectScreen (MODIFY)

- Replace hardcoded `allSkins` array with `SkinType.allCases`
- Each row: `skin.displayName` + checkmark if `skinManager.currentSkinType == type`
- On tap: `skinManager.switch(to: type)`
- Remove "Phase 2" tags — all 7 skins available

## AppPreferences (MODIFY)

Add:
```swift
var skinType: String {
    get { UserDefaults.standard.string(forKey: "skin_type") ?? "default" }
    set { UserDefaults.standard.set(newValue, forKey: "skin_type") }
}
```

## Font Registration

5 custom fonts from Android's `res/font/` directory, copied to iOS bundle:

| Font | File | Weight |
|------|------|--------|
| Cinzel | `cinzel_regular.ttf` | 77 KB |
| Noto Serif SC | `noto_serif_sc_regular.ttf` | 14.8 MB |
| Playfair Display | `playfair_display_regular.ttf` | 193 KB |
| Pacifico | `pacifico_regular.ttf` | 329 KB |
| Cormorant Garamond | `cormorant_garamond.ttf` | 1.2 MB |

- Copy to `Sources/Resources/fonts/`
- Register in `Info.plist` under `UIAppFonts`
- `SkinManager.init()` calls `registerFonts()` using `CTFontManagerRegisterFontsForURL`

## Implementation Order (Bottom-up)

1. Add `SkinType` enum to `SkinProtocol.swift`
2. Extend `SkinProtocol` with ~15 new tokens + protocol extension defaults
3. Add `skinType` to `AppPreferences`
4. Create `SkinManager` class
5. Copy 5 font files + register in Info.plist
6. Rename `DefaultSkin` → `SweetSkin`, update values
7. Create 6 new skin files: `GothicSkin`, `ChineseSkin`, `ClassicSkin`, `NavySkin`, `CountrySkin`, `VictorianSkin`
8. Create `ImageFrame` component
9. Modify `LolitaCard` — dark mode border support
10. Modify `LolitaSection` — dark mode divider/accent
11. Modify `LolitaNavigationBar` — blur toggle
12. Modify `ThemeSelectScreen` — live switching
13. Modify `LolitaApp` — inject `SkinManager`
14. Update all ~20 consumer files: `DefaultSkin` → `SkinManager`
15. Build + verify each skin at runtime

## Out of Scope (Future Phases)

| Item | Target Phase |
|------|-------------|
| Custom icons (45+ per skin, 7 skins) | Phase 3b |
| Entrance animations (SkinItemAppear, stagger) | Phase 3c |
| Navigation transitions (slide/fade per skin) | Phase 3c |
| Ripple effects + click particles | Phase 3c |
| Background particle systems | Phase 3c |
| Tab indicator animations | Phase 3c |
| Haze/blur nav bar (no SwiftUI equivalent) | Phase 3d |
| Taobao order import | Phase 4 |
| Smart recommendations UI | Phase 5 |
| Backup/restore + shared library sync | Phase 6 |
