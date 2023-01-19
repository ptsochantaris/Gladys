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
            type: .dynamic,
            targets: ["GladysCommon"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/ExceptionCatcher", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0"),
        .package(url: "https://github.com/cezheng/Fuzi", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "GladysCommon",
            dependencies: ["ExceptionCatcher",
                           "Fuzi",
                           .product(name: "AsyncHTTPClient", package: "async-http-client")]
        )
    ]
)
