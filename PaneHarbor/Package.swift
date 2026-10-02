// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PaneHarbor",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PaneHarbor", targets: ["PaneHarbor"])
    ],
    dependencies: [
        .package(path: "Vendor/ZIPFoundation")
    ],
    targets: [
        .executableTarget(
            name: "PaneHarbor",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/PaneHarbor",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PaneHarborTests",
            dependencies: [
                "PaneHarbor",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Tests/PaneHarborTests"
        )
    ]
)
