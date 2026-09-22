// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ambient",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Ambient",
            path: "Sources/Ambient"
        )
    ]
)
