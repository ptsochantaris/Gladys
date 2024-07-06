// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GladysAppKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "GladysAppKit",
            targets: ["GladysAppKit"]
        )
    ],
    dependencies: [
        .package(path: "../GladysUI"),
        .package(path: "../GladysCommon")
    ],
    targets: [
        .target(
            name: "GladysAppKit",
            dependencies: ["GladysCommon", "GladysUI"]
        )
    ]
)
