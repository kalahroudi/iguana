// swift-tools-version:6.0
import PackageDescription

// No third-party dependencies: keeps the binary small and the memory footprint low.
let package = Package(
    name: "iguana",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Iguana", targets: ["Iguana"]),
        .library(name: "IguanaKit", targets: ["IguanaKit"]),
    ],
    targets: [
        // UI-free core: matching, sectioning, naming. Unit tested.
        .target(name: "IguanaKit"),
        // The menu bar app.
        .executableTarget(name: "Iguana", dependencies: ["IguanaKit"]),
        .testTarget(name: "IguanaKitTests", dependencies: ["IguanaKit"]),
    ],
    swiftLanguageModes: [.v5]
)
