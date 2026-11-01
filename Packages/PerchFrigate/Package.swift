// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchFrigate",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchFrigate", targets: ["PerchFrigate"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchFrigate", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchFrigateTests", dependencies: ["PerchFrigate"]),
    ],
    swiftLanguageModes: [.v6]
)
