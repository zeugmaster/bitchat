// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "bitchat",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "bitchat",
            targets: ["bitchat"]
        ),
    ],
    dependencies: [
        // Local CashuSwift package in parent directory
        .package(path: "../CashuSwift")
    ],
    targets: [
        .executableTarget(
            name: "bitchat",
            dependencies: [
                .product(name: "CashuSwift", package: "CashuSwift")
            ],
            path: "bitchat"
        ),
    ]
)