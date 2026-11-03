// swift-tools-version: 6.0

// Used by xtool (Linux/WSL builds and on-device installs). CI and Xcode still use project.yml.

import PackageDescription

let package = Package(
    name: "Ahoge",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Ahoge", targets: ["Ahoge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "Ahoge",
            dependencies: ["SwiftSoup", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Ahoge",
            // XcodeGen writes Info.plist and compiles the asset catalog; xtool uses Info-xtool.plist and the icon PNG (see xtool.yml).
            exclude: ["Info.plist", "Assets.xcassets"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
