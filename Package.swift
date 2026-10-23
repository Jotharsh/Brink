// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Edgelit",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic and drawing: spectrum analysis, smoothing, palettes, the glow renderer. No windows.
        .target(name: "EdgelitCore"),
        // The menu bar app: overlay windows, audio capture, notification watching.
        .executableTarget(name: "Edgelit", dependencies: ["EdgelitCore"]),
        .testTarget(name: "EdgelitCoreTests", dependencies: ["EdgelitCore"]),
    ]
)
