// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GladysAppKit",
    platforms: [
        .macOS(.v12)
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
