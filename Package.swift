// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "yamete",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "yamete",
            targets: ["yamete"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "yamete",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
