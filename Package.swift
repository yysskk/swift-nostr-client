// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NostrClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "NostrClient",
            targets: ["NostrClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.18.0"),
    ],
    targets: [
        .target(
            name: "NostrClient",
            dependencies: [
                .product(name: "P256K", package: "secp256k1.swift"),
            ]
        ),
        .testTarget(
            name: "NostrClientTests",
            dependencies: ["NostrClient"]
        ),
    ]
)
