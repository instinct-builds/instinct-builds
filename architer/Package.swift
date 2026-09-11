// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ARCHITER",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArchiterCore", targets: ["ArchiterCore"]),
        .executable(name: "architer", targets: ["ARCHITERApp"]),
    ],
    targets: [
        .target(name: "ArchiterCore"),
        .executableTarget(
            name: "ARCHITERApp",
            dependencies: ["ArchiterCore"]
        ),
        .testTarget(
            name: "ArchiterCoreTests",
            dependencies: ["ArchiterCore"]
        ),
    ]
)
