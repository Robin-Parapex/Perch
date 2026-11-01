// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchAI",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchAI", targets: ["PerchAI"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchAI", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchAITests", dependencies: ["PerchAI"]),
    ],
    swiftLanguageModes: [.v6]
)
