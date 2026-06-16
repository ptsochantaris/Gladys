// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "GladysUIKit",
    platforms: [
        .iOS(.v26),
        .visionOS(.v26)
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

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: [
        // .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances")
    ])
    target.swiftSettings = settings
}
