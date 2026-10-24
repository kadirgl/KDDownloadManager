// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KDDownloadManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KDDownloadManager",
            path: "Sources/KDDownloadManager",
            resources: [
                // Kullanılan Phosphor ikonları (bkz. Views/Icons.swift) ve lisansı.
                .process("Resources")
            ]
        )
    ]
)
