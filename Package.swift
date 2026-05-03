// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Needle",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Needle", targets: ["Needle"])
    ],
    targets: [
        .executableTarget(
            name: "Needle",
            path: "Sources/Needle"
        )
    ]
)
