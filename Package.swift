// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BetterPaste",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BetterPaste", targets: ["BetterPaste"])
    ],
    targets: [
        .executableTarget(
            name: "BetterPaste",
            path: "Sources/BetterPaste",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(name: "BetterPasteTests", dependencies: ["BetterPaste"])
    ]
)
