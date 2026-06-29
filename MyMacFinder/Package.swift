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
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.20"))
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
