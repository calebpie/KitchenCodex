// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Capture",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "Capture", targets: ["Capture"]),
    ],
    dependencies: [
        .package(path: "../Intelligence"),
    ],
    targets: [
        .target(
            name: "Capture",
            dependencies: [
                .product(name: "Intelligence", package: "Intelligence"),
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "CaptureTests",
            dependencies: ["Capture"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
