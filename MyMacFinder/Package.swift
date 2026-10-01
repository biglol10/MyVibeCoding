// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyMacFinder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MyMacFinder", targets: ["MyMacFinder"])
    ],
    dependencies: [
        .package(path: "Vendor/ZIPFoundation")
    ],
    targets: [
        .executableTarget(
            name: "MyMacFinder",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/MyMacFinder",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MyMacFinderTests",
            dependencies: [
                "MyMacFinder",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Tests/MyMacFinderTests"
        )
    ]
)
