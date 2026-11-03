// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchPlex",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchPlex", targets: ["PerchPlex"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchPlex", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(
            name: "PerchPlexTests",
            dependencies: ["PerchPlex"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
