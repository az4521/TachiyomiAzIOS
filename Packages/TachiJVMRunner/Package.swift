// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TachiJVMRunner",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "TachiJVMRunner", targets: ["TachiJVMRunner"]),
    ],
    targets: [
        .target(
            name: "CJVMBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "TachiJVMRunner",
            dependencies: ["CJVMBridge"]
        ),
        .testTarget(
            name: "TachiJVMRunnerTests",
            dependencies: ["TachiJVMRunner"]
        ),
    ]
)
