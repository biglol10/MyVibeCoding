// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMacClean",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyMacCleanCore", targets: ["MyMacCleanCore"]),
        .library(name: "MyMacCleanAppSupport", targets: ["MyMacCleanAppSupport"]),
        .executable(name: "MyMacCleanApp", targets: ["MyMacCleanApp"])
    ],
    targets: [
        .target(name: "MyMacCleanCore"),
        .target(
            name: "MyMacCleanAppSupport",
            dependencies: ["MyMacCleanCore"]
        ),
        .executableTarget(
            name: "MyMacCleanApp",
            dependencies: ["MyMacCleanCore", "MyMacCleanAppSupport"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MyMacCleanCoreTests",
            dependencies: ["MyMacCleanCore"]
        ),
        .testTarget(
            name: "MyMacCleanAppSupportTests",
            dependencies: ["MyMacCleanAppSupport", "MyMacCleanCore"]
        )
    ]
)
