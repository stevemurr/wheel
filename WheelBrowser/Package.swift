// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WheelBrowser",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.3.0"),
        .package(url: "https://github.com/unum-cloud/usearch", from: "2.0.0"),
        .package(path: "../Packages/SqliteVec"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "WheelBrowser",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "USearch", package: "usearch"),
                "SqliteVec",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "Sources/WheelBrowser",
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        )
    ]
)
