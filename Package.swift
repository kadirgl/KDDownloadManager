// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KDDownloadManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/phosphor-icons/swift", from: "2.1.0")
    ],
    targets: [
        .executableTarget(
            name: "KDDownloadManager",
            dependencies: [
                .product(name: "PhosphorSwift", package: "swift")
            ],
            path: "Sources/KDDownloadManager"
        )
    ]
)
