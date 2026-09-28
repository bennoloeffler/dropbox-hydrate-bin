// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dropbox-hydrate-bin",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HydrateCore"),
        .executableTarget(name: "dropbox-hydrate-bin", dependencies: ["HydrateCore"]),
        .testTarget(name: "HydrateCoreTests", dependencies: ["HydrateCore"]),
    ]
)
