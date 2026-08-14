// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMacSearch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyMacSearchCore", targets: ["MyMacSearchCore"]),
        .library(name: "MyMacSearchAppSupport", targets: ["MyMacSearchAppSupport"]),
        .executable(name: "MyMacSearchApp", targets: ["MyMacSearchApp"])
    ],
    targets: [
        .target(
            name: "MyMacSearchCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "MyMacSearchAppSupport",
            dependencies: ["MyMacSearchCore"]
        ),
        .executableTarget(
            name: "MyMacSearchApp",
            dependencies: ["MyMacSearchCore", "MyMacSearchAppSupport"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "MyMacSearchCoreTests",
            dependencies: ["MyMacSearchCore"]
        ),
        .testTarget(
            name: "MyMacSearchAppSupportTests",
            dependencies: ["MyMacSearchAppSupport", "MyMacSearchCore"]
        )
    ]
)
