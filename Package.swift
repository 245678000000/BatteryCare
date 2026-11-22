// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BatteryCare",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", path: "Sources/CSMC",
                linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "Shared", dependencies: ["CSMC"], path: "Sources/Shared",
                linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "BatteryCare", dependencies: ["Shared"], path: "Sources/BatteryCare"),
        .executableTarget(name: "batterycare-helper", dependencies: ["Shared"], path: "Sources/Helper"),
    ]
)
