// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GladysUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
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
