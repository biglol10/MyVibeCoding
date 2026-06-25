// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptureStudio",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CaptureStudio", targets: ["CaptureStudio"])
    ],
    targets: [
        .executableTarget(
            name: "CaptureStudio",
            path: "Sources/CaptureStudio",
            linkerSettings: [
                .linkedFramework("AVKit")
            ]
        ),
        .testTarget(
            name: "CaptureStudioTests",
            dependencies: ["CaptureStudio"],
            path: "Tests/CaptureStudioTests"
        )
    ]
)
