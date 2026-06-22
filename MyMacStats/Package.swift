// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMacStats",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyMacStatsCore", targets: ["MyMacStatsCore"]),
        .library(name: "MyMacStatsAppSupport", targets: ["MyMacStatsAppSupport"]),
        .executable(name: "MyMacStatsApp", targets: ["MyMacStatsApp"])
    ],
    targets: [
        .target(
            name: "MyMacStatsCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "MyMacStatsAppSupport",
            dependencies: ["MyMacStatsCore"]
        ),
        .executableTarget(
            name: "MyMacStatsApp",
            dependencies: ["MyMacStatsCore", "MyMacStatsAppSupport"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MyMacStatsCoreTests",
            dependencies: ["MyMacStatsCore"]
        ),
        .testTarget(
            name: "MyMacStatsAppSupportTests",
            dependencies: ["MyMacStatsAppSupport", "MyMacStatsCore"]
        )
    ]
)
