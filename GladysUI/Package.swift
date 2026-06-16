// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "GladysUI",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "GladysUI",
            targets: ["GladysUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ptsochantaris/CallbackURLKit-VisionOS-Fork", branch: "master"),
        .package(path: "../GladysCommon")
    ],
    targets: [
        .target(
            name: "GladysUI",
            dependencies: ["GladysCommon",
                           .product(name: "CallbackURLKit", package: "CallbackURLKit-VisionOS-Fork")]
        )
    ]
)

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: [
        // .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances")
    ])
    target.swiftSettings = settings
}
