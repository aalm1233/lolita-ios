// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lolita",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "lolita",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources",
            exclude: ["Info.plist", "Lolita.entitlements"],
            resources: [.process("Resources/fonts"), .process("Resources/skin-art"),
                        .process("Resources/Assets.xcassets"), .copy("Resources/builtin")]
        ),
        .testTarget(name: "LolitaTests", dependencies: ["lolita"], path: "Tests"),
        // Native interaction tests run through the Lolita-Ledger-UI Xcode scheme.
        .testTarget(name: "LolitaUITests", dependencies: [], path: "UITests")
    ]
)
