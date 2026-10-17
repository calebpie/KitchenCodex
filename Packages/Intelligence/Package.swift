// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Intelligence",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "Intelligence", targets: ["Intelligence"]),
    ],
    targets: [
        .target(
            name: "Intelligence",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "IntelligenceTests",
            dependencies: ["Intelligence"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
