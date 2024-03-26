// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenAI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .visionOS(.v1),
        .tvOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OpenAI",
            targets: ["OpenAI"]),
    ],
    targets: [
        .target(
            name: "OpenAI",
            dependencies: []),
        .testTarget(
            name: "OpenAITests",
            dependencies: ["OpenAI"]),
    ]
)
