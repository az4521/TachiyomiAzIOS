// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TachiyomiAZRunner",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "AidokuRunner", targets: ["AidokuRunner"])
    ],
    dependencies: [
        // Aidoku still compiles its GPL legacy source implementation for the
        // macOS target. The iOS JVM source path does not instantiate it.
        .package(url: "https://github.com/Skittyblock/Wasm3", branch: "main")
    ],
    targets: [
        .target(name: "AidokuRunner", dependencies: ["Wasm3"])
    ]
)
