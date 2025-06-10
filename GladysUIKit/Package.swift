// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GladysUIKit",
    platforms: [
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "GladysUIKit",
            targets: ["GladysUIKit"]
        )
    ],
    dependencies: [
        .package(path: "../GladysUI"),
        .package(path: "../GladysCommon")
    ],
    targets: [
        .target(
            name: "GladysUIKit",
            dependencies: ["GladysCommon", "GladysUI"]
        )
    ]
)
