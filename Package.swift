// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "bitchat",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "bitchat",
            targets: ["bitchat"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "bitchat",
            dependencies: [
            ],
            path: "bitchat",
            resources: [
                .process("Assets.xcassets"),
                .process("LaunchScreen.storyboard"),
                .process("Info-iOS.plist"),
                .process("Info-macOS.plist")
            ]
        )
    ]
)