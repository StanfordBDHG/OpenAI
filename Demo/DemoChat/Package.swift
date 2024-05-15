// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DemoChat",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(
            name: "DemoChat",
            targets: ["DemoChat"]
        ),
    ],
    dependencies: [
        .package(name: "OpenAI", path: "../.."),
    ],
    targets: [
        .target(
            name: "DemoChat",
            dependencies: [
                "OpenAI",
            ],
            path: "Sources"
        ),
    ]
)
