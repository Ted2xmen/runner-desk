// swift-tools-version:6.0
import PackageDescription

// DeskCore: Runner Desk's pure rules. Foundation and ShelfRunnerCore only;
// no AppKit, SwiftUI, file system or processes (scripts/gate.sh checks the imports).
let package = Package(
    name: "DeskCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DeskCore", targets: ["DeskCore"]),
    ],
    dependencies: [
        // Protocol types (protocol v1) from the runner's own library. No tags yet:
        // pinned to a revision of origin/main; move to a version tag once the runner tags one.
        .package(url: "https://github.com/Ted2xmen/shelf-runner", revision: "e41a716f1f0b925463b5517d1e75ce772a9d24f6"),
    ],
    targets: [
        .target(name: "DeskCore", dependencies: [.product(name: "ShelfRunnerCore", package: "shelf-runner")]),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"], resources: [.copy("Fixtures")]),
    ]
)
