// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyCal",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MyCalCore"),
        .executableTarget(name: "MyCal", dependencies: ["MyCalCore"]),
        .testTarget(name: "MyCalCoreTests", dependencies: ["MyCalCore"]),
    ],
    swiftLanguageModes: [.v5]
)
