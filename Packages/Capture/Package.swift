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
        .package(path: "../Units"),
    ],
    targets: [
        .target(
            name: "Capture",
            dependencies: [
                .product(name: "Intelligence", package: "Intelligence"),
                .product(name: "Units", package: "Units"),
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "CaptureTests",
            dependencies: [
                "Capture",
                .product(name: "Units", package: "Units"),
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
