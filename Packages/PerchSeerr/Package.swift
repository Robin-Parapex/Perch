// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchSeerr",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchSeerr", targets: ["PerchSeerr"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchSeerr", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchSeerrTests", dependencies: ["PerchSeerr"]),
    ],
    swiftLanguageModes: [.v6]
)
