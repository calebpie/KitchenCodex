// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RecipeModel",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "RecipeModel", targets: ["RecipeModel"]),
    ],
    targets: [
        .target(
            name: "RecipeModel",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "RecipeModelTests",
            dependencies: ["RecipeModel"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
