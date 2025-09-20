// swift-tools-version: 6.2

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

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: [
        // .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances")
    ])
    target.swiftSettings = settings
}
