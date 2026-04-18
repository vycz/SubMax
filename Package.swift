// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SubMax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SubMax", targets: ["SubMax"]),
        .library(name: "SubMaxCore", targets: ["SubMaxCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SubMaxCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SubMax",
            dependencies: ["SubMaxCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "SubMaxCoreTests",
            dependencies: ["SubMaxCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
