// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchDesign",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchDesign", targets: ["PerchDesign"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchDesign", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchDesignTests", dependencies: ["PerchDesign"]),
    ],
    swiftLanguageModes: [.v6]
)
