// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Scheduler",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "Scheduler", targets: ["Scheduler"]),
    ],
    dependencies: [
        .package(path: "../KnowledgeBase"),
    ],
    targets: [
        .target(
            name: "Scheduler",
            dependencies: [
                .product(name: "KnowledgeBase", package: "KnowledgeBase"),
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "SchedulerTests",
            dependencies: ["Scheduler"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
