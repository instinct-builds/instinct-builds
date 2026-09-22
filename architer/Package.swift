// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ARCHITER",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArchiterCore", targets: ["ArchiterCore"]),
        .executable(name: "architer", targets: ["ARCHITERApp"]),
        .executable(name: "architer-render", targets: ["ARCHITERRender"]),
    ],
    targets: [
        .target(name: "ArchiterCore"),
        .target(name: "ARCHITERUI", dependencies: ["ArchiterCore"]),
        .executableTarget(
            name: "ARCHITERApp",
            dependencies: ["ARCHITERUI"]
        ),
        .executableTarget(
            name: "ARCHITERRender",
            dependencies: ["ARCHITERUI"]
        ),
        .testTarget(
            name: "ArchiterCoreTests",
            dependencies: ["ArchiterCore"]
        ),
    ]
)
