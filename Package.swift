// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pocket",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pocket", targets: ["Pocket"])],
    targets: [
        .executableTarget(name: "Pocket", resources: [.process("Resources")]),
        .target(name: "PocketTestSupport", path: "Tests/PocketTestSupport"),
        .testTarget(name: "PocketTests", dependencies: ["Pocket", "PocketTestSupport"]),
        .testTarget(name: "PocketAnimationTests", dependencies: ["Pocket", "PocketTestSupport"]),
    ]
)
