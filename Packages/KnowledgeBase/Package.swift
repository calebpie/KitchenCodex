// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KnowledgeBase",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "KnowledgeBase", targets: ["KnowledgeBase"]),
    ],
    targets: [
        .target(
            name: "KnowledgeBase",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "KnowledgeBaseTests",
            dependencies: ["KnowledgeBase"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
