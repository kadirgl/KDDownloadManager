// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KDDownloadManager",
    // Kaynak koddaki metinler Türkçe; İngilizcesi Resources/Localizable.xcstrings'te.
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KDDownloadManager",
            path: "Sources/KDDownloadManager",
            // Çeviriler SwiftPM'in kaynak paketiyle değil scripts/strings.sh ile derlenip doğrudan
            // uygulamanın Contents/Resources'ına konuyor; böylece SwiftUI'nin Text("…") metinleri ve
            // String(localized:) ek bir `bundle:` vermeden Bundle.main'den çevriliyor.
            exclude: ["Resources"]
        )
    ]
)
