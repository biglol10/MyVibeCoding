// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ZIPFoundation",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ZIPFoundation", targets: ["ZIPFoundation"])],
    targets: [.target(name: "ZIPFoundation", path: "Sources/ZIPFoundation")],
    swiftLanguageModes: [.v5]
)
