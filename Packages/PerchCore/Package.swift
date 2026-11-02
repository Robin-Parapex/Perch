// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchCore",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchCore", targets: ["PerchCore"])],
    targets: [
        .target(name: "PerchCore"),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ],
    swiftLanguageModes: [.v6]
)
