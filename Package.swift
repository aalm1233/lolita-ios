// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lolita",
    platforms: [.iOS(.v17), .macOS(.v11)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "lolita",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: "Sources"
        ),
    ]
)
