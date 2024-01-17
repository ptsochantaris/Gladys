// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GladysCommon",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "GladysCommon",
            targets: ["GladysCommon"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/ExceptionCatcher", from: "2.0.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", branch: "development"),
        .package(url: "https://github.com/ptsochantaris/semalot", branch: "main"),
        .package(url: "https://github.com/ptsochantaris/lista", branch: "main"),
        .package(url: "https://github.com/ptsochantaris/pop-timer", branch: "main"),
        .package(url: "https://github.com/ptsochantaris/maintini", branch: "main")
    ],
    targets: [
        .target(
            name: "GladysCommon",
            dependencies: ["ExceptionCatcher",
                           "SwiftSoup",
                           "ZIPFoundation",
                           .product(name: "Lista", package: "lista"),
                           .product(name: "Maintini", package: "maintini"),
                           .product(name: "Semalot", package: "semalot"),
                           .product(name: "PopTimer", package: "pop-timer")]
        )
    ]
)
