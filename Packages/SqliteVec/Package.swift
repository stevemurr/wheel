// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SqliteVec",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SqliteVec",
            targets: ["SqliteVec"]
        )
    ],
    targets: [
        .target(
            name: "CSqliteVec",
            cSettings: [
                .define("SQLITE_VEC_STATIC"),
                .define("SQLITE_CORE"),
                // NEON is auto-detected on ARM, no need to set flags
                .headerSearchPath("include"),
                .unsafeFlags(["-O3"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "SqliteVec",
            dependencies: ["CSqliteVec"]
        ),
        .testTarget(
            name: "SqliteVecTests",
            dependencies: ["SqliteVec"]
        )
    ]
)
