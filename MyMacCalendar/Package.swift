// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMacCalendar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MyMacCalendarCore", targets: ["MyMacCalendarCore"]),
        .executable(name: "MyMacCalendar", targets: ["MyMacCalendar"])
    ],
    targets: [
        .target(
            name: "MyMacCalendarCore",
            path: "Sources/MyMacCalendarCore"
        ),
        .executableTarget(
            name: "MyMacCalendar",
            dependencies: ["MyMacCalendarCore"],
            path: "Sources/MyMacCalendar"
        ),
        .testTarget(
            name: "MyMacCalendarCoreTests",
            dependencies: ["MyMacCalendarCore"],
            path: "Tests/MyMacCalendarCoreTests"
        )
    ]
)
