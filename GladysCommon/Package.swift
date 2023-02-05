// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "GladysCommon",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "GladysCommon",
            targets: ["GladysCommon"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/ExceptionCatcher", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0"),
        .package(url: "https://github.com/cezheng/Fuzi", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.0.0")
    ],
    targets: [
        .target(
            name: "GladysCommon",
            dependencies: ["ExceptionCatcher",
                           "Fuzi",
                           "ZIPFoundation",
                           .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                           .product(name: "AsyncHTTPClient", package: "async-http-client")]
        )
    ]
)
