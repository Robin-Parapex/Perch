// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchHome",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchHome", targets: ["PerchHome"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchHome", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchHomeTests", dependencies: ["PerchHome"]),
    ],
    swiftLanguageModes: [.v6]
)
