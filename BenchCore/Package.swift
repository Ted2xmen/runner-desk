// swift-tools-version:6.0
import PackageDescription

// BenchCore: Shelf Bench's pure rules. Foundation and ShelfBridgeCore only;
// no AppKit, SwiftUI, file system or processes (scripts/gate.sh checks the imports).
let package = Package(
    name: "BenchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BenchCore", targets: ["BenchCore"]),
    ],
    dependencies: [
        // Protocol types (protocol v2) from Bridge's own library. No tags yet:
        // pinned to a revision of origin/main; move to a version tag once Bridge tags one.
        .package(url: "https://github.com/Ted2xmen/shelf-bridge", revision: "f815abd57072efef572f5244cee62b7ae1bd3866"),
    ],
    targets: [
        .target(name: "BenchCore", dependencies: [.product(name: "ShelfBridgeCore", package: "shelf-bridge")]),
        .testTarget(name: "BenchCoreTests", dependencies: ["BenchCore"], resources: [.copy("Fixtures")]),
    ]
)
