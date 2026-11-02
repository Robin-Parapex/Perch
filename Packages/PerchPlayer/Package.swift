// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchPlayer",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchPlayer", targets: ["PerchPlayer"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchPlayer", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchPlayerTests", dependencies: ["PerchPlayer"]),
    ],
    swiftLanguageModes: [.v6]
)
