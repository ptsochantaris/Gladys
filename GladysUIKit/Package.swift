// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GladysUIKit",
    platforms: [
        .iOS(.v16),
        .visionOS(.v1)
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
