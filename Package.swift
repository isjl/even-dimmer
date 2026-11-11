// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EvenDimmer",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Auto-updates. Pinned to an exact version on purpose.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(
            name: "SystemControls",
            path: "Sources/SystemControls"
        ),
        .executableTarget(
            name: "EvenDimmer",
            dependencies: [
                "SystemControls",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/EvenDimmer",
            linkerSettings: [
                // Sparkle.framework is embedded in the app's Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
