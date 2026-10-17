// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nutrition",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "Nutrition", targets: ["Nutrition"]),
    ],
    dependencies: [
        .package(path: "../Intelligence"),
        .package(path: "../Units"),
    ],
    targets: [
        .target(
            name: "Nutrition",
            dependencies: [
                .product(name: "Intelligence", package: "Intelligence"),
                .product(name: "Units", package: "Units"),
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "NutritionTests",
            dependencies: ["Nutrition"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
