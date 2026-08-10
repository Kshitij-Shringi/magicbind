// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MagicBind",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MagicBindCore",
            path: "Sources/MagicBindCore"
        ),
        .executableTarget(
            name: "MagicBind",
            dependencies: ["MagicBindCore"],
            path: "Sources/MagicBind"
        )
    ]
)
