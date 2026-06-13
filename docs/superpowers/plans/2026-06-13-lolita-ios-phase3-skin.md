# Lolita iOS Phase 3 — 皮肤系统 (Skin System) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the 6 remaining skins from Android (Gothic, Chinese, Classic, Navy, Country, Victorian) to iOS — colors, fonts, and shapes only. Add SkinManager for runtime switching with persistence.

**Architecture:** Extend `SkinProtocol` with ~15 new tokens (fonts, image frame, dark mode borders, blur toggles). Create `SkinManager` ObservableObject wrapping `any SkinProtocol`. 6 new skin classes + rename `DefaultSkin` → `SweetSkin`. Replace `@EnvironmentObject var skin: DefaultSkin` with `var skinManager: SkinManager` in ~20 consumer files.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+. No new dependencies. 5 custom fonts copied from Android project.

---

## File Structure Map

```
Sources/
├── LolitaApp.swift                          # MODIFY — inject SkinManager
├── Info.plist                               # MODIFY — register UIAppFonts
├── Resources/
│   └── fonts/                               # CREATE dir
│       ├── cinzel_regular.ttf               # COPY from Android
│       ├── noto_serif_sc_regular.ttf        # COPY from Android
│       ├── playfair_display_regular.ttf     # COPY from Android
│       ├── pacifico_regular.ttf             # COPY from Android
│       └── cormorant_garamond.ttf           # COPY from Android
├── Data/
│   └── Preferences/
│       └── AppPreferences.swift             # MODIFY — add skinType
├── UI/
│   ├── Theme/
│   │   ├── SkinProtocol.swift               # MODIFY — add SkinType enum, extend protocol
│   │   ├── DefaultSkin.swift                # MODIFY — rename to SweetSkin
│   │   ├── SkinManager.swift                # CREATE
│   │   ├── GothicSkin.swift                 # CREATE
│   │   ├── ChineseSkin.swift                # CREATE
│   │   ├── ClassicSkin.swift                # CREATE
│   │   ├── NavySkin.swift                   # CREATE
│   │   ├── CountrySkin.swift                # CREATE
│   │   └── VictorianSkin.swift              # CREATE
│   ├── Component/
│   │   ├── ImageFrame.swift                 # CREATE
│   │   ├── LolitaCard.swift                 # MODIFY — dark mode border
│   │   ├── LolitaSection.swift              # MODIFY — dark mode divider/accent
│   │   └── LolitaNavigationBar.swift        # MODIFY — blur toggle
│   ├── Screen/
│   │   ├── Settings/
│   │   │   └── ThemeSelectScreen.swift      # MODIFY — live switching
│   │   ├── Item/
│   │   │   ├── ItemDetailScreen.swift       # MODIFY — skin → skinManager
│   │   │   └── ItemEditScreen.swift         # MODIFY — skin → skinManager
│   │   ├── Coordinate/
│   │   │   ├── CoordinateDetailScreen.swift  # MODIFY — skin → skinManager
│   │   │   ├── CoordinateEditScreen.swift    # MODIFY — skin → skinManager
│   │   │   └── CoordinateListScreen.swift    # MODIFY — skin → skinManager
│   │   ├── Outfit/
│   │   │   ├── OutfitLogDetailScreen.swift   # MODIFY — skin → skinManager
│   │   │   ├── OutfitLogEditScreen.swift     # MODIFY — skin → skinManager
│   │   │   ├── OutfitLogListScreen.swift     # MODIFY — skin → skinManager
│   │   │   └── QuickOutfitLogScreen.swift    # MODIFY — skin → skinManager
│   │   ├── Location/
│   │   │   ├── LocationDetailScreen.swift    # MODIFY — skin → skinManager
│   │   │   └── LocationEditScreen.swift      # MODIFY — skin → skinManager
│   │   ├── Payment/
│   │   │   ├── PaymentCalendarScreen.swift   # MODIFY — skin → skinManager
│   │   │   └── PaymentManageScreen.swift     # MODIFY — skin → skinManager
│   │   ├── Stats/
│   │   │   └── StatsPageScreen.swift         # MODIFY — skin → skinManager
│   │   └── Wishlist/
│   │       └── WishlistScreen.swift          # MODIFY — skin → skinManager
```

---

### Task 1: Add SkinType enum + extend SkinProtocol with new tokens

**Files:**
- Modify: `Sources/UI/Theme/SkinProtocol.swift`

- [ ] **Step 1: Add SkinType enum at top of file**

Add this at the top of `Sources/UI/Theme/SkinProtocol.swift`, before the `protocol SkinProtocol` declaration:

```swift
import SwiftUI

enum SkinType: String, CaseIterable {
    case `default` = "DEFAULT"
    case gothic = "GOTHIC"
    case chinese = "CHINESE"
    case classic = "CLASSIC"
    case navy = "NAVY"
    case country = "COUNTRY"
    case victorian = "VICTORIAN"

    var displayName: String {
        switch self {
        case .default: return "甜美粉"
        case .gothic: return "哥特暗黑"
        case .chinese: return "中华风韵"
        case .classic: return "经典优雅"
        case .navy: return "清风水手"
        case .country: return "田园牧歌"
        case .victorian: return "维多利亚"
        }
    }
}
```

- [ ] **Step 2: Add new tokens to SkinProtocol**

Insert the following new properties into the `SkinProtocol` protocol body, after the existing `compactCardInnerPadding` property:

```swift
    // Font
    var fontName: String? { get }
    var fontDisplayName: String { get }

    // Image frame
    var imageFrameElevation: CGFloat { get }
    var imageFrameBorderStroke: (color: Color, width: CGFloat)? { get }
    var imageFrameBorderStrokeDark: (color: Color, width: CGFloat)? { get }
    var imageFramePadding: CGFloat { get }

    // Dark mode borders
    var cardBorderStrokeDark: (color: Color, width: CGFloat)? { get }
    var sectionDividerColorDark: Color { get }
    var sectionAccentColorDark: Color { get }

    // Shapes
    var buttonCornerRadius: CGFloat { get }

    // Blur
    var navBarBlurEnabled: Bool { get }
    var dialogBlurEnabled: Bool { get }

    // Tab bar
    var tabBarBackgroundColor: Color { get }
    var tabBarBackgroundColorDark: Color { get }
```

- [ ] **Step 3: Add protocol extension defaults**

Add this extension block at the end of `Sources/UI/Theme/SkinProtocol.swift`, after the closing `}` of the protocol:

```swift
extension SkinProtocol {
    var fontName: String? { nil }
    var fontDisplayName: String { "系统默认" }

    var imageFrameElevation: CGFloat { 2 }
    var imageFrameBorderStroke: (color: Color, width: CGFloat)? { nil }
    var imageFrameBorderStrokeDark: (color: Color, width: CGFloat)? { nil }
    var imageFramePadding: CGFloat { 0 }

    var cardBorderStrokeDark: (color: Color, width: CGFloat)? { nil }
    var sectionDividerColorDark: Color { sectionDividerColor }
    var sectionAccentColorDark: Color { sectionAccentColor }

    var buttonCornerRadius: CGFloat { cornerRadiusM }

    var navBarBlurEnabled: Bool { false }
    var dialogBlurEnabled: Bool { false }

    var tabBarBackgroundColor: Color { cardColor }
    var tabBarBackgroundColorDark: Color { cardColorDark }
}
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build
```

Expected: Build succeeds (DefaultSkin doesn't yet implement new tokens, but protocol extensions provide defaults).

- [ ] **Step 5: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/SkinProtocol.swift
git commit -m "feat: add SkinType enum and extend SkinProtocol with font/image/dark-mode tokens"
```

---

### Task 2: Add skinType to AppPreferences

**Files:**
- Modify: `Sources/Data/Preferences/AppPreferences.swift`

- [ ] **Step 1: Add skinType property**

In `Sources/Data/Preferences/AppPreferences.swift`, replace the existing `currentSkinType` property with `skinType` (renamed to match spec):

```swift
import Foundation

final class AppPreferences {
    private let defaults = UserDefaults.standard

    var isFirstLaunch: Bool {
        get { defaults.object(forKey: "isFirstLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isFirstLaunch") }
    }

    var skinType: String {
        get { defaults.string(forKey: "skin_type") ?? "DEFAULT" }
        set { defaults.set(newValue, forKey: "skin_type") }
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
git add Sources/Data/Preferences/AppPreferences.swift
git commit -m "feat: rename currentSkinType to skinType with skin_type key"
```

---

### Task 3: Create SkinManager class

**Files:**
- Create: `Sources/UI/Theme/SkinManager.swift`

- [ ] **Step 1: Create SkinManager.swift**

Create `Sources/UI/Theme/SkinManager.swift`:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

final class SkinManager: ObservableObject {
    @Published var current: any SkinProtocol
    @Published var currentSkinType: SkinType = .default

    private let preferences = AppPreferences()

    init() {
        let storedType = SkinType(rawValue: preferences.skinType) ?? .default
        self.currentSkinType = storedType
        self.current = SkinManager.create(storedType)
    }

    func switch(to type: SkinType) {
        current = SkinManager.create(type)
        currentSkinType = type
        preferences.skinType = type.rawValue
    }

    var customFont: Font? {
        guard let name = current.fontName else { return nil }
        return Font.custom(name, size: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }

    static func create(_ type: SkinType) -> any SkinProtocol {
        switch type {
        case .default: return SweetSkin()
        case .gothic: return GothicSkin()
        case .chinese: return ChineseSkin()
        case .classic: return ClassicSkin()
        case .navy: return NavySkin()
        case .country: return CountrySkin()
        case .victorian: return VictorianSkin()
        }
    }
}
```

- [ ] **Step 2: Build to verify (will fail — SweetSkin not yet created)**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | head -20
```

Expected: Build FAILS with "Cannot find 'SweetSkin' in scope". This is expected — Task 6 will create it.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/SkinManager.swift
git commit -m "feat: add SkinManager for runtime skin switching with persistence"
```

---

### Task 4: Copy fonts from Android + register in Info.plist

**Files:**
- Copy: 5 font files from `../lolita/app/src/main/res/font/` to `Sources/Resources/fonts/`
- Modify: `Sources/Info.plist`

- [ ] **Step 1: Create fonts directory and copy files**

```bash
mkdir -p /Users/dengtong/code/lolita-ios/Sources/Resources/fonts
cp /Users/dengtong/code/lolita/app/src/main/res/font/cinzel_regular.ttf /Users/dengtong/code/lolita-ios/Sources/Resources/fonts/
cp /Users/dengtong/code/lolita/app/src/main/res/font/noto_serif_sc_regular.ttf /Users/dengtong/code/lolita-ios/Sources/Resources/fonts/
cp /Users/dengtong/code/lolita/app/src/main/res/font/playfair_display_regular.ttf /Users/dengtong/code/lolita-ios/Sources/Resources/fonts/
cp /Users/dengtong/code/lolita/app/src/main/res/font/pacifico_regular.ttf /Users/dengtong/code/lolita-ios/Sources/Resources/fonts/
cp /Users/dengtong/code/lolita/app/src/main/res/font/cormorant_garamond.ttf /Users/dengtong/code/lolita-ios/Sources/Resources/fonts/
```

Expected: 5 files copied successfully.

- [ ] **Step 2: Register fonts in Info.plist**

In `Sources/Info.plist`, add the `UIAppFonts` key inside the `<dict>`:

```xml
    <key>UIAppFonts</key>
    <array>
        <string>cinzel_regular.ttf</string>
        <string>noto_serif_sc_regular.ttf</string>
        <string>playfair_display_regular.ttf</string>
        <string>pacifico_regular.ttf</string>
        <string>cormorant_garamond.ttf</string>
    </array>
```

Insert this block before the closing `</dict>` tag.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/Resources/fonts/ Sources/Info.plist
git commit -m "feat: add 5 custom fonts from Android project"
```

---

### Task 5: Rename DefaultSkin → SweetSkin

**Files:**
- Modify: `Sources/UI/Theme/DefaultSkin.swift`

- [ ] **Step 1: Rename class and add new token overrides**

Replace the entire contents of `Sources/UI/Theme/DefaultSkin.swift`:

```swift
import SwiftUI

final class SweetSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 1.0, green: 0.41, blue: 0.71)       // #FF69B4
    let secondaryColor = Color(red: 0.90, green: 0.90, blue: 0.98)     // #E6E6FA
    let backgroundColor = Color(red: 1.0, green: 0.94, blue: 0.97)     // #FFF0F5
    let accentColor = Color(red: 1.0, green: 0.41, blue: 0.71)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.91, green: 0.12, blue: 0.55)   // #E91E8C
    let secondaryColorDark = Color(red: 0.30, green: 0.25, blue: 0.35)
    let backgroundColorDark = Color(red: 0.10, green: 0.08, blue: 0.10)
    let accentColorDark = Color(red: 0.91, green: 0.12, blue: 0.55)
    let cardColorDark = Color(red: 0.20, green: 0.16, blue: 0.18).opacity(0.8)

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 1.0, green: 0.41, blue: 0.71),
        Color(red: 0.94, green: 0.70, blue: 0.85)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.50, green: 0.10, blue: 0.30),
        Color(red: 0.30, green: 0.10, blue: 0.20)
    ]

    // Corner radii (matching Android DEFAULT: 8/16/24)
    let cornerRadiusS: CGFloat = 8
    let cornerRadiusM: CGFloat = 16
    let cornerRadiusL: CGFloat = 24
    let buttonCornerRadius: CGFloat = 16

    // Spacing (8pt grid)
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 1
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 20

    // Top bar
    let topBarDecoration = "✿"
    let topBarDecorationAlpha: Double = 0.7
    let topBarBlurEnabled = true

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 1.0, green: 0.75, blue: 0.80)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 2
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 0.5
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = nil
    let fontDisplayName = "系统默认"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -20
```

Expected: Build FAILS because consumer files still reference `DefaultSkin`. This is expected — Task 15 will update them.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/DefaultSkin.swift
git commit -m "refactor: rename DefaultSkin to SweetSkin with new token overrides"
```

---

### Task 6: Create GothicSkin

**Files:**
- Create: `Sources/UI/Theme/GothicSkin.swift`

- [ ] **Step 1: Create GothicSkin.swift**

Create `Sources/UI/Theme/GothicSkin.swift`:

```swift
import SwiftUI

final class GothicSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.29, green: 0.05, blue: 0.31)      // #4A0E4E
    let secondaryColor = Color(red: 0.55, green: 0.0, blue: 0.0)       // #8B0000
    let backgroundColor = Color(red: 0.96, green: 0.94, blue: 0.96)    // #F5F0F5
    let accentColor = Color(red: 0.29, green: 0.05, blue: 0.31)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.73, green: 0.53, blue: 0.99)   // #BB86FC
    let secondaryColorDark = Color(red: 0.60, green: 0.20, blue: 0.25)
    let backgroundColorDark = Color(red: 0.10, green: 0.10, blue: 0.18) // #1A1A2E
    let accentColorDark = Color(red: 0.73, green: 0.53, blue: 0.99)
    let cardColorDark = Color(red: 0.18, green: 0.18, blue: 0.27).opacity(0.8) // #2D2D44

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.29, green: 0.05, blue: 0.31),
        Color(red: 0.20, green: 0.02, blue: 0.22)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.15, green: 0.08, blue: 0.18),
        Color(red: 0.08, green: 0.04, blue: 0.10)
    ]

    // Corner radii (GOTHIC: 4/8/12)
    let cornerRadiusS: CGFloat = 4
    let cornerRadiusM: CGFloat = 8
    let cornerRadiusL: CGFloat = 12
    let buttonCornerRadius: CGFloat = 6

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 2
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 14
    let cardGap: CGFloat = 16

    // Top bar
    let topBarDecoration = "✝"
    let topBarDecorationAlpha: Double = 0.5
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 2
    let sectionDividerColor = Color(red: 0.35, green: 0.10, blue: 0.35)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 3
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 1
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "Cinzel-Regular"
    let fontDisplayName = "Cinzel"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: Build FAILS (consumer files still reference `DefaultSkin`). GothicSkin itself compiles clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/GothicSkin.swift
git commit -m "feat: add Gothic skin (dark purple, Cinzel font, sharp corners)"
```

---

### Task 7: Create ChineseSkin

**Files:**
- Create: `Sources/UI/Theme/ChineseSkin.swift`

- [ ] **Step 1: Create ChineseSkin.swift**

Create `Sources/UI/Theme/ChineseSkin.swift`:

```swift
import SwiftUI

final class ChineseSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.77, green: 0.12, blue: 0.23)      // #C41E3A
    let secondaryColor = Color(red: 0.85, green: 0.65, blue: 0.13)     // #DAA520
    let backgroundColor = Color(red: 1.0, green: 0.97, blue: 0.94)     // #FFF8F0
    let accentColor = Color(red: 0.77, green: 0.12, blue: 0.23)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 1.0, green: 0.42, blue: 0.42)    // #FF6B6B
    let secondaryColorDark = Color(red: 0.85, green: 0.65, blue: 0.13)
    let backgroundColorDark = Color(red: 0.10, green: 0.08, blue: 0.06) // #1A1410
    let accentColorDark = Color(red: 1.0, green: 0.42, blue: 0.42)
    let cardColorDark = Color(red: 0.18, green: 0.15, blue: 0.13).opacity(0.8) // #2D2520

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.77, green: 0.12, blue: 0.23),
        Color(red: 0.85, green: 0.40, blue: 0.30)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.40, green: 0.10, blue: 0.15),
        Color(red: 0.25, green: 0.06, blue: 0.10)
    ]

    // Corner radii (CHINESE: 2/4/8)
    let cornerRadiusS: CGFloat = 2
    let cornerRadiusM: CGFloat = 4
    let cornerRadiusL: CGFloat = 8
    let buttonCornerRadius: CGFloat = 4

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 2
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 12

    // Top bar
    let topBarDecoration = "☁"
    let topBarDecorationAlpha: Double = 0.6
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.85, green: 0.65, blue: 0.13)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 3
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 1
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "NotoSerifSC-Regular"
    let fontDisplayName = "Noto Serif SC"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: ChineseSkin compiles clean (consumer file failures expected).

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/ChineseSkin.swift
git commit -m "feat: add Chinese skin (vermillion red, Noto Serif SC, near-square corners)"
```

---

### Task 8: Create ClassicSkin

**Files:**
- Create: `Sources/UI/Theme/ClassicSkin.swift`

- [ ] **Step 1: Create ClassicSkin.swift**

Create `Sources/UI/Theme/ClassicSkin.swift`:

```swift
import SwiftUI

final class ClassicSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.45, green: 0.18, blue: 0.22)      // #722F37
    let secondaryColor = Color(red: 0.55, green: 0.27, blue: 0.07)     // #8B4513
    let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.94)    // #FAF5F0
    let accentColor = Color(red: 0.45, green: 0.18, blue: 0.22)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)   // #C49098
    let secondaryColorDark = Color(red: 0.65, green: 0.40, blue: 0.20)
    let backgroundColorDark = Color(red: 0.10, green: 0.08, blue: 0.08) // #1A1515
    let accentColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)
    let cardColorDark = Color(red: 0.18, green: 0.15, blue: 0.15).opacity(0.8) // #2D2525

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.45, green: 0.18, blue: 0.22),
        Color(red: 0.55, green: 0.27, blue: 0.20)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.25, green: 0.10, blue: 0.12),
        Color(red: 0.15, green: 0.06, blue: 0.08)
    ]

    // Corner radii (CLASSIC: 6/12/16)
    let cornerRadiusS: CGFloat = 6
    let cornerRadiusM: CGFloat = 12
    let cornerRadiusL: CGFloat = 16
    let buttonCornerRadius: CGFloat = 8

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 2
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 16

    // Top bar
    let topBarDecoration = "♠"
    let topBarDecorationAlpha: Double = 0.5
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.55, green: 0.27, blue: 0.07)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 3
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 1
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "PlayfairDisplay-Regular"
    let fontDisplayName = "Playfair Display"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: ClassicSkin compiles clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/ClassicSkin.swift
git commit -m "feat: add Classic skin (wine burgundy, Playfair Display, refined corners)"
```

---

### Task 9: Create NavySkin

**Files:**
- Create: `Sources/UI/Theme/NavySkin.swift`

- [ ] **Step 1: Create NavySkin.swift**

Create `Sources/UI/Theme/NavySkin.swift`:

```swift
import SwiftUI

final class NavySkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.29, green: 0.56, blue: 0.85)      // #4A90D9
    let secondaryColor = Color(red: 0.85, green: 0.65, blue: 0.13)     // #DAA520
    let backgroundColor = Color(red: 0.94, green: 0.97, blue: 1.0)     // #F0F8FF
    let accentColor = Color(red: 0.29, green: 0.56, blue: 0.85)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.48, green: 0.72, blue: 0.96)   // #7AB8F5
    let secondaryColorDark = Color(red: 0.85, green: 0.65, blue: 0.13)
    let backgroundColorDark = Color(red: 0.05, green: 0.11, blue: 0.16) // #0D1B2A
    let accentColorDark = Color(red: 0.48, green: 0.72, blue: 0.96)
    let cardColorDark = Color(red: 0.11, green: 0.18, blue: 0.27).opacity(0.8) // #1B2D44

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.29, green: 0.56, blue: 0.85),
        Color(red: 0.45, green: 0.70, blue: 0.90)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.10, green: 0.25, blue: 0.45),
        Color(red: 0.05, green: 0.15, blue: 0.30)
    ]

    // Corner radii (NAVY: 7/14/20)
    let cornerRadiusS: CGFloat = 7
    let cornerRadiusM: CGFloat = 14
    let cornerRadiusL: CGFloat = 20
    let buttonCornerRadius: CGFloat = 14

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 1.5
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 18

    // Top bar
    let topBarDecoration = "⚓"
    let topBarDecorationAlpha: Double = 0.6
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.29, green: 0.56, blue: 0.85)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 2
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 0.5
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "Pacifico-Regular"
    let fontDisplayName = "Pacifico"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: NavySkin compiles clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/NavySkin.swift
git commit -m "feat: add Navy skin (sky blue, Pacifico font, soft corners)"
```

---

### Task 10: Create CountrySkin

**Files:**
- Create: `Sources/UI/Theme/CountrySkin.swift`

- [ ] **Step 1: Create CountrySkin.swift**

Create `Sources/UI/Theme/CountrySkin.swift`:

```swift
import SwiftUI

final class CountrySkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.49, green: 0.60, blue: 0.41)      // #7C9A69
    let secondaryColor = Color(red: 0.77, green: 0.40, blue: 0.35)     // #C56759
    let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.91)    // #F9F4E8
    let accentColor = Color(red: 0.49, green: 0.60, blue: 0.41)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.66, green: 0.79, blue: 0.60)   // #A8C99A
    let secondaryColorDark = Color(red: 0.77, green: 0.40, blue: 0.35)
    let backgroundColorDark = Color(red: 0.12, green: 0.15, blue: 0.11) // #1F261C
    let accentColorDark = Color(red: 0.66, green: 0.79, blue: 0.60)
    let cardColorDark = Color(red: 0.18, green: 0.21, blue: 0.16).opacity(0.8) // #2D3529

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.49, green: 0.60, blue: 0.41),
        Color(red: 0.65, green: 0.75, blue: 0.55)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.20, green: 0.28, blue: 0.15),
        Color(red: 0.12, green: 0.18, blue: 0.10)
    ]

    // Corner radii (COUNTRY: 10/20/28)
    let cornerRadiusS: CGFloat = 10
    let cornerRadiusM: CGFloat = 20
    let cornerRadiusL: CGFloat = 28
    let buttonCornerRadius: CGFloat = 18

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 1
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 18
    let cardGap: CGFloat = 14

    // Top bar
    let topBarDecoration = "✿"
    let topBarDecorationAlpha: Double = 0.7
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.49, green: 0.60, blue: 0.41)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 2
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 0.5
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "CormorantGaramond-Regular"
    let fontDisplayName = "Cormorant Garamond"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: CountrySkin compiles clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/CountrySkin.swift
git commit -m "feat: add Country skin (sage green, Cormorant Garamond, softest corners)"
```

---

### Task 11: Create VictorianSkin

**Files:**
- Create: `Sources/UI/Theme/VictorianSkin.swift`

- [ ] **Step 1: Create VictorianSkin.swift**

Create `Sources/UI/Theme/VictorianSkin.swift`:

```swift
import SwiftUI

final class VictorianSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.48, green: 0.12, blue: 0.23)      // #7B1E3A
    let secondaryColor = Color(red: 0.72, green: 0.53, blue: 0.04)     // #B8860B
    let backgroundColor = Color(red: 1.0, green: 0.97, blue: 0.94)     // #FFF8F0
    let accentColor = Color(red: 0.48, green: 0.12, blue: 0.23)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)   // #C49098
    let secondaryColorDark = Color(red: 0.72, green: 0.53, blue: 0.04)
    let backgroundColorDark = Color(red: 0.10, green: 0.07, blue: 0.06) // #1A1210
    let accentColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)
    let cardColorDark = Color(red: 0.17, green: 0.12, blue: 0.09).opacity(0.8) // #2C1E18

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.48, green: 0.12, blue: 0.23),
        Color(red: 0.60, green: 0.25, blue: 0.30)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.25, green: 0.08, blue: 0.12),
        Color(red: 0.15, green: 0.05, blue: 0.08)
    ]

    // Corner radii (VICTORIAN: 6/12/16)
    let cornerRadiusS: CGFloat = 6
    let cornerRadiusM: CGFloat = 12
    let cornerRadiusL: CGFloat = 16
    let buttonCornerRadius: CGFloat = 8

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 3
    let cardBorderStroke: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 1) // gold 1pt
    let cardBorderStrokeDark: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 0.5) // gold 0.5pt
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 20

    // Top bar
    let topBarDecoration = "⚜"
    let topBarDecorationAlpha: Double = 0.5
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.72, green: 0.53, blue: 0.04)

    // Image frame
    let imageFrameBorderStroke: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 1)
    let imageFrameBorderStrokeDark: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 0.5)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 4
    let featuredCardInnerPadding: CGFloat = 24

    // Compact card
    let compactCardElevation: CGFloat = 1
    let compactCardInnerPadding: CGFloat = 10

    // Font
    let fontName: String? = "CormorantGaramond-Regular"
    let fontDisplayName = "Cormorant Garamond"
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: VictorianSkin compiles clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Theme/VictorianSkin.swift
git commit -m "feat: add Victorian skin (burgundy, gold borders, Cormorant Garamond)"
```

---

### Task 12: Create ImageFrame component

**Files:**
- Create: `Sources/UI/Component/ImageFrame.swift`

- [ ] **Step 1: Create ImageFrame.swift**

Create `Sources/UI/Component/ImageFrame.swift`:

```swift
import SwiftUI

struct ImageFrame<Content: View>: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder let content: () -> Content

    private var isDark: Bool { colorScheme == .dark }

    private var currentBorder: (color: Color, width: CGFloat)? {
        if isDark, let dark = skinManager.current.imageFrameBorderStrokeDark {
            return dark
        }
        return skinManager.current.imageFrameBorderStroke
    }

    var body: some View {
        content()
            .padding(skinManager.current.imageFramePadding)
            .background(
                RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                    .fill(Color.clear)
            )
            .overlay(
                Group {
                    if let border = currentBorder {
                        RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                            .stroke(border.color, lineWidth: border.width)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM))
            .shadow(
                color: .black.opacity(0.08),
                radius: skinManager.current.imageFrameElevation,
                y: skinManager.current.imageFrameElevation * 0.5
            )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1 | tail -5
```

Expected: Build FAILS (consumer files still reference `DefaultSkin`). ImageFrame itself compiles clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Component/ImageFrame.swift
git commit -m "feat: add ImageFrame component with skin-aware borders and elevation"
```

---

### Task 13: Update LolitaCard with dark mode border support

**Files:**
- Modify: `Sources/UI/Component/LolitaCard.swift`

- [ ] **Step 1: Replace @EnvironmentObject and add dark mode border logic**

In `Sources/UI/Component/LolitaCard.swift`, replace the entire file contents:

```swift
import SwiftUI

enum CardVariant {
    case `default`
    case gallery
    case featured
    case compact
}

struct LolitaCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var skinManager: SkinManager

    let variant: CardVariant
    @ViewBuilder let content: () -> Content

    init(variant: CardVariant = .default, @ViewBuilder content: @escaping () -> Content) {
        self.variant = variant
        self.content = content
    }

    private var isDark: Bool { colorScheme == .dark }

    private var currentBorder: (color: Color, width: CGFloat)? {
        if isDark, let dark = skinManager.current.cardBorderStrokeDark {
            return dark
        }
        return skinManager.current.cardBorderStroke
    }

    private var elevation: CGFloat {
        switch variant {
        case .default: return skinManager.current.cardElevation
        case .gallery: return skinManager.current.galleryCardElevation
        case .featured: return skinManager.current.featuredCardElevation
        case .compact: return skinManager.current.compactCardElevation
        }
    }

    private var padding: CGFloat {
        switch variant {
        case .default: return skinManager.current.cardInnerPadding
        case .gallery: return skinManager.current.galleryCardInnerPadding
        case .featured: return skinManager.current.featuredCardInnerPadding
        case .compact: return skinManager.current.compactCardInnerPadding
        }
    }

    private var cardBackground: Color {
        isDark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                    .fill(cardBackground)
            )
            .overlay(
                Group {
                    if let border = currentBorder {
                        RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                            .stroke(border.color, lineWidth: border.width)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM))
            .shadow(
                color: .black.opacity(0.08),
                radius: elevation,
                y: elevation * 0.5
            )
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Component/LolitaCard.swift
git commit -m "feat: add dark mode border support to LolitaCard via SkinManager"
```

---

### Task 14: Update LolitaSection with dark mode colors

**Files:**
- Modify: `Sources/UI/Component/LolitaSection.swift`

- [ ] **Step 1: Replace @EnvironmentObject and add dark mode color resolution**

In `Sources/UI/Component/LolitaSection.swift`, replace the entire file contents:

```swift
import SwiftUI

struct LolitaSection<Content: View>: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) var colorScheme

    let title: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    private var isDark: Bool { colorScheme == .dark }

    private var dividerColor: Color {
        isDark ? skinManager.current.sectionDividerColorDark : skinManager.current.sectionDividerColor
    }

    private var accentColorResolved: Color {
        isDark ? skinManager.current.sectionAccentColorDark : skinManager.current.sectionAccentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rectangle()
                    .fill(accentColorResolved)
                    .frame(width: skinManager.current.sectionAccentWidth)
                    .cornerRadius(skinManager.current.sectionAccentWidth / 2)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let label = actionLabel {
                    Button(label) { onAction?() }
                        .font(.subheadline)
                        .foregroundColor(skinManager.current.accentColor)
                }
            }
            .padding(.horizontal, skinManager.current.spacingL)
            .padding(.vertical, skinManager.current.spacingM)

            Divider()
                .overlay(dividerColor)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, skinManager.current.spacingL)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Component/LolitaSection.swift
git commit -m "feat: add dark mode divider/accent color support to LolitaSection"
```

---

### Task 15: Update LolitaNavigationBar with blur toggle

**Files:**
- Modify: `Sources/UI/Component/LolitaNavigationBar.swift`

- [ ] **Step 1: Replace @EnvironmentObject and add conditional blur**

In `Sources/UI/Component/LolitaNavigationBar.swift`, replace the entire file contents:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LolitaNavigationBar: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var skinManager: SkinManager

    let title: String
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil

    private var isDark: Bool { colorScheme == .dark }
    private var gradient: [Color] { isDark ? skinManager.current.gradientColorsDark : skinManager.current.gradientColors }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea(edges: .top)

            HStack(spacing: 8) {
                if showBack {
                    Button(action: { onBack?() }) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }

                Text(skinManager.current.topBarDecoration)
                    .font(.system(size: 16))
                    .opacity(skinManager.current.topBarDecorationAlpha)
                    .foregroundColor(.white)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, skinManager.current.spacingL)
            .padding(.vertical, 12)
        }
        .frame(height: 44 + safeAreaTop)
    }

    private var safeAreaTop: CGFloat {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 0
        #else
        return 0
        #endif
    }
}

// MARK: - Convenience modifier

extension View {
    func lolitaNavBar(title: String, showBack: Bool = false, onBack: (() -> Void)? = nil) -> some View {
        VStack(spacing: 0) {
            LolitaNavigationBar(title: title, showBack: showBack, onBack: onBack)
            self
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Component/LolitaNavigationBar.swift
git commit -m "feat: update LolitaNavigationBar to use SkinManager"
```

---

### Task 16: Update LolitaApp entry point to inject SkinManager

**Files:**
- Modify: `Sources/LolitaApp.swift`

- [ ] **Step 1: Replace DefaultSkin with SkinManager**

In `Sources/LolitaApp.swift`, replace the entire file contents:

```swift
import SwiftUI

@main
struct LolitaApp: App {
    @StateObject private var skinManager = SkinManager()

    init() {
        try? AppModule.shared.setupDatabase()
    }

    var body: some Scene {
        WindowGroup {
            LolitaNavHost()
                .environmentObject(skinManager)
                .task {
                    try? await AppModule.shared.seedIfNeeded()
                }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/LolitaApp.swift
git commit -m "feat: inject SkinManager at app entry point, remove DefaultSkin"
```

---

### Task 17: Update ThemeSelectScreen for live switching

**Files:**
- Modify: `Sources/UI/Screen/Settings/ThemeSelectScreen.swift`

- [ ] **Step 1: Replace hardcoded list with SkinType-driven live switching**

In `Sources/UI/Screen/Settings/ThemeSelectScreen.swift`, replace the entire file contents:

```swift
import SwiftUI

struct ThemeSelectScreen: View {
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        List {
            ForEach(SkinType.allCases, id: \.rawValue) { type in
                Button {
                    skinManager.switch(to: type)
                } label: {
                    HStack {
                        Text(type.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        if skinManager.currentSkinType == type {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .lolitaNavBar(title: "主题选择")
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/Settings/ThemeSelectScreen.swift
git commit -m "feat: wire ThemeSelectScreen to SkinManager for live skin switching"
```

---

### Task 18: Update all consumer files — DefaultSkin → SkinManager

**Files:**
- Modify: 15 screen files + ThemeSelectScreen already done above

This is a mechanical find-and-replace across 15 files. The pattern is:
- `@EnvironmentObject var skin: DefaultSkin` → `@EnvironmentObject var skinManager: SkinManager`
- `skin.` → `skinManager.current.`

- [ ] **Step 1: Update Screen/Item files**

In `Sources/UI/Screen/Item/ItemDetailScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Item/ItemEditScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

- [ ] **Step 2: Update Screen/Coordinate files**

In `Sources/UI/Screen/Coordinate/CoordinateDetailScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Coordinate/CoordinateEditScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Coordinate/CoordinateListScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

- [ ] **Step 3: Update Screen/Outfit files**

In `Sources/UI/Screen/Outfit/OutfitLogDetailScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Outfit/OutfitLogEditScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Outfit/OutfitLogListScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Outfit/QuickOutfitLogScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

- [ ] **Step 4: Update Screen/Location files**

In `Sources/UI/Screen/Location/LocationDetailScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Location/LocationEditScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

- [ ] **Step 5: Update Screen/Payment files**

In `Sources/UI/Screen/Payment/PaymentCalendarScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Payment/PaymentManageScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

- [ ] **Step 6: Update remaining screen files**

In `Sources/UI/Screen/Stats/StatsPageScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

In `Sources/UI/Screen/Wishlist/WishlistScreen.swift`:
- Replace `@EnvironmentObject var skin: DefaultSkin` with `@EnvironmentObject var skinManager: SkinManager`
- Replace all `skin.` references with `skinManager.current.`

- [ ] **Step 7: Build to verify everything compiles**

```bash
cd /Users/dengtong/code/lolita-ios && swift build 2>&1
```

Expected: Build SUCCEEDS with zero errors.

- [ ] **Step 8: Commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add Sources/UI/Screen/
git commit -m "feat: migrate all consumer screens from DefaultSkin to SkinManager"
```

---

### Task 19: Final build verification

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

```bash
cd /Users/dengtong/code/lolita-ios && swift build --clean 2>&1
```

Expected: Build SUCCEEDS. No warnings related to skin/protocol/types.

- [ ] **Step 2: Verify all 7 skins are referenced**

```bash
cd /Users/dengtong/code/lolita-ios
grep -r "SkinType\." Sources/ --include="*.swift"
```

Expected output should show all 7 cases referenced in `SkinManager.create()` and `SkinType.allCases`.

- [ ] **Step 3: Verify no remaining DefaultSkin references**

```bash
cd /Users/dengtong/code/lolita-ios
grep -r "DefaultSkin" Sources/ --include="*.swift"
```

Expected: No results (except possibly in comments). The `DefaultSkin.swift` file still exists but the class is renamed to `SweetSkin`.

- [ ] **Step 4: Verify font files exist in bundle**

```bash
ls -la /Users/dengtong/code/lolita-ios/Sources/Resources/fonts/
```

Expected: 5 .ttf files listed.

- [ ] **Step 5: Final commit**

```bash
cd /Users/dengtong/code/lolita-ios
git add -A
git commit -m "chore: final verification — clean build, all 7 skins, no DefaultSkin refs"
```
