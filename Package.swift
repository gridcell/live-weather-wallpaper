// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WeatherWallpaper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WeatherWallpaper", path: "Sources/WeatherWallpaper")
    ]
)
