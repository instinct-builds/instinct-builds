// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ASSSETS",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AsssetsCore", targets: ["AsssetsCore"]),
        .executable(name: "asssets", targets: ["AsssetsApp"]),
    ],
    targets: [
        .target(name: "AsssetsCore"),
        .executableTarget(
            name: "AsssetsApp",
            dependencies: ["AsssetsCore"],
            resources: [.copy("StarterLibrary.zip")]
        ),
        .testTarget(name: "AsssetsCoreTests", dependencies: ["AsssetsCore"]),
    ]
)
