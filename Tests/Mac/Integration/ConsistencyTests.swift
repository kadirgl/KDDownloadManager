import CryptoKit
import Foundation
import Testing
@testable import KDDownloadManager

/// Mac uygulaması, Windows uygulaması ve Chrome eklentisi aynı değerleri paylaşmalı; biri değişip öteki
/// unutulursa eklenti bir sistemde bağlanamaz.
@Suite("Mac / Windows / eklenti tutarlılığı")
@MainActor
struct ConsistencyTests {
    let repo = TestEnvironment.repository

    private func text(_ path: String) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
    }

    private func manifest() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("ChromeExtension/manifest.json"))) as! [String: Any]
    }

    @Test("Paketlenmemiş eklentinin kimliği manifest'teki 'key'den çıkıyor")
    func unpackedIDMatchesKey() throws {
        let key = try #require(manifest()["key"] as? String)
        let der = try #require(Data(base64Encoded: key))
        // Chrome: SHA-256'nın ilk 16 baytı, her onaltılık hane a–p harfine çevrilir.
        let id = SHA256.hash(data: der).prefix(16).flatMap { byte in [byte >> 4, byte & 0x0F] }
            .map { String(UnicodeScalar(UInt8(ascii: "a") + $0)) }.joined()
        #expect(id == BrowserExtension.unpackedExtensionID)
    }

    @Test("Windows aynı eklenti kimliklerini ve mağaza durumunu kullanıyor")
    func windowsMatchesMac() throws {
        let windows = try text("Windows/KDDownloadManager/Support/BrowserExtension.cs")
        #expect(windows.contains(#"StoreExtensionId = "\#(BrowserExtension.storeExtensionID)""#))
        #expect(windows.contains(#"UnpackedExtensionId = "\#(BrowserExtension.unpackedExtensionID)""#))
        #expect(windows.contains("StoreListingLive = \(BrowserExtension.storeListingLive)"))
        #expect((BrowserExtension.storeURL == nil) == !BrowserExtension.storeListingLive)
    }

    @Test("Köprü portu üç tarafta aynı")
    func port() throws {
        #expect(try text("Sources/KDDownloadManager/Bridge/ExtensionBridge.swift").contains("return 47615"))
        #expect(try text("Windows/KDDownloadManager/Bridge/ExtensionBridge.cs").contains("47615"))
        let extensionCode = try ["background.js", "popup.js", "menu.js", "app.js"].map { try text("ChromeExtension/" + $0) }.joined()
        #expect(extensionCode.contains("47615"))
    }

    @Test("Eklentinin kalite değerleri uygulamanın tanıdıkları")
    func qualities() throws {
        let known = Set(VideoQuality.allCases.map(\.rawValue))
        func values(_ pattern: String, in code: String) throws -> [String] {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
                .compactMap { Range($0.range(at: 1), in: code).map { String(code[$0]) } }
        }
        let app = try text("ChromeExtension/app.js")
        let list = try #require(app.range(of: "QUALITIES = [").flatMap { start in
            app[start.upperBound...].range(of: "];").map { String(app[start.upperBound..<$0.lowerBound]) }
        })
        let offered = try values(#"id:\s*["']([a-z0-9]+)["']"#, in: list)
        #expect(Set(offered) == known, "eklentinin listesi: \(offered)")
        let code = try ["popup.js", "menu.js", "background.js", "videos.js"].map { try text("ChromeExtension/" + $0) }.joined()
        for value in try values(#"quality:\s*["']([a-z0-9]+)["']"#, in: code) {
            #expect(known.contains(value), "eklentide bilinmeyen kalite: \(value)")
        }
    }

    @Test("Video siteleri listesi eklentiyle aynı (çerezler doğru siteye gitsin)")
    func videoHosts() throws {
        let code = try text("ChromeExtension/app.js")
        for host in DownloadSource.videoHostList {
            #expect(code.contains("'\(host)'") || code.contains("\"\(host)\""), "eklentide yok: \(host)")
        }
    }
}
