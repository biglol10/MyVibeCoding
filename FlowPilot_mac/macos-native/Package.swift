// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowPilotNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FlowPilotNative", targets: ["FlowPilotNative"])
    ],
    targets: [
        .target(
            name: "FlowPilotNativeCore",
            path: "Sources/FlowPilotNativeCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "FlowPilotNative",
            dependencies: ["FlowPilotNativeCore"],
            path: "Sources/FlowPilotNative"
        ),
        .testTarget(
            name: "FlowPilotNativeCoreTests",
            dependencies: ["FlowPilotNativeCore"],
            path: "Tests/FlowPilotNativeCoreTests"
        )
    ]
)
