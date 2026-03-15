// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WheelBrowser",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../../fabric"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.3.0"),
        .package(url: "https://github.com/Ryu0118/swift-readability", from: "0.3.0"),
        .package(url: "https://github.com/rryam/VecturaKit", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "WheelBrowser",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Readability", package: "swift-readability"),
                .product(name: "VecturaKit", package: "VecturaKit"),
                .product(name: "Fabric", package: "fabric"),
            ],
            path: "Sources/WheelBrowser",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/Extensions"),
                .copy("Resources/WidgetRuntime"),
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
            dependencies: [
                "WheelBrowser",
                .product(name: "Fabric", package: "fabric"),
            ],
            path: "Tests/WheelBrowserTests",
            resources: [
                .copy("Agent/Fixtures"),
                .copy("ExtractionFixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
