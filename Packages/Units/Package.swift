// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Units",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "Units", targets: ["Units"]),
    ],
    targets: [
        .target(
            name: "Units",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "UnitsTests",
            dependencies: ["Units"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
