// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMarkdownViewer",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MyMarkdownCore", targets: ["MyMarkdownCore"]),
               .executable(name: "MyMarkdownViewer", targets: ["MyMarkdownViewer"])],
    targets: [
        .target(name: "MyMarkdownCore", path: "Sources/Core"),
        .executableTarget(name: "MyMarkdownViewer", dependencies: ["MyMarkdownCore"],
                          path: "Sources/App", resources: [.copy("Resources/Editor"), .copy("Resources/AppIcon.icns"), .copy("Resources/ThirdPartyNotices.txt")]),
        .testTarget(name: "MyMarkdownCoreTests", dependencies: ["MyMarkdownCore"], path: "Tests/CoreTests")
    ]
)
