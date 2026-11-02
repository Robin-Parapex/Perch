// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerchTautulli",
    platforms: [.tvOS("26.0")],
    products: [.library(name: "PerchTautulli", targets: ["PerchTautulli"])],
    dependencies: [.package(path: "../PerchCore")],
    targets: [
        .target(name: "PerchTautulli", dependencies: [.product(name: "PerchCore", package: "PerchCore")]),
        .testTarget(name: "PerchTautulliTests", dependencies: ["PerchTautulli"]),
    ],
    swiftLanguageModes: [.v6]
)
