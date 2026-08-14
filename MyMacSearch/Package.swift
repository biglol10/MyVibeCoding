// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMacSearch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyMacSearchCore", targets: ["MyMacSearchCore"])
    ],
    targets: [
        .target(
            name: "MyMacSearchCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MyMacSearchCoreTests",
            dependencies: ["MyMacSearchCore"]
        )
    ]
)
