// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchTrakt",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchTrakt", targets: ["PerchTrakt"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchTrakt", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchTraktTests", dependencies: ["PerchTrakt"]),
    ],
    swiftLanguageModes: [.v6]
)
