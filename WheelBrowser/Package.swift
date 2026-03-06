// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WheelBrowser",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.3.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.6.0"),
        .package(url: "https://github.com/rryam/VecturaKit", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "WheelBrowser",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "VecturaKit", package: "VecturaKit"),
            ],
            path: "Sources/WheelBrowser",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/WidgetSystem"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "wheel-mcp-bridge",
            dependencies: [],
            path: "Sources/WheelMCPBridge",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "WheelBrowserTests",
            dependencies: ["WheelBrowser"],
            path: "Tests/WheelBrowserTests",
            resources: [
                .copy("Agent/Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
