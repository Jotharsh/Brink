// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brink",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic and drawing: spectrum analysis, smoothing, palettes, the glow renderer. No windows.
        .target(name: "BrinkCore"),
        // The menu bar app: overlay windows, audio capture, notification watching.
        .executableTarget(name: "Brink", dependencies: ["BrinkCore"]),
        .testTarget(name: "BrinkCoreTests", dependencies: ["BrinkCore"]),
    ]
)
