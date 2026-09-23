// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ASSSETS",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AsssetsCore", targets: ["AsssetsCore"]),
        .executable(name: "asssets", targets: ["AsssetsApp"]),
        .executable(name: "asssets-mockgen", targets: ["AsssetsMockgen"]),
    ],
    targets: [
        .target(name: "AsssetsCore"),
        .executableTarget(
            name: "AsssetsApp",
            dependencies: ["AsssetsCore"]
        ),
        .executableTarget(name: "AsssetsMockgen", dependencies: ["AsssetsCore"]),
        .testTarget(name: "AsssetsCoreTests", dependencies: ["AsssetsCore"]),
    ]
)
