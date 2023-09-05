// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GladysUI",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "GladysUI",
            targets: ["GladysUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/phimage/CallbackURLKit", from: "3.0.0"),
        .package(path: "../GladysCommon")
    ],
    targets: [
        .target(
            name: "GladysUI",
            dependencies: ["GladysCommon",
                           "CallbackURLKit"]
        )
    ]
)
