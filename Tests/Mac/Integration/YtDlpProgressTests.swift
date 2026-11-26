import Foundation
import Testing
@testable import KDDownloadManager

/// Video indirmenin ilerlemesi. yt-dlp görüntüyü ve sesi ayrı parçalar halinde indirip birleştiriyor; uygulama
/// parçaları toplayıp tek bir ilerleme gösteriyor. Sahte yt-dlp (betik), Windows'ta kaydedilmiş gerçek bir YouTube
/// indirmesinin çıktısını birebir yeniden oynatır; aria2c'nin satır sonu koymadığı yerler dahil.
@Suite("Video indirme ilerlemesi (sahte yt-dlp)", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct YtDlpProgressTests {
    @Test("aria2 satırına yapışan 'parça bitti' mesajı ayrılıyor")
    func splitsGluedMessage() {
        let glued = #"[#caef46 70MiB/77MiB(91%) CN:8 DL:74MiB]KDPROG {"status": "finished", "downloaded_bytes": 80911999}"#
        #expect(YtDlpEngine.outputLines(glued) == [
            "[#caef46 70MiB/77MiB(91%) CN:8 DL:74MiB]",
            #"KDPROG {"status": "finished", "downloaded_bytes": 80911999}"#,
        ])
        #expect(YtDlpEngine.outputLines("[#acafac 1.0MiB/3.2MiB(30%) CN:1 DL:2.3MiB]") == ["[#acafac 1.0MiB/3.2MiB(30%) CN:1 DL:2.3MiB]"])
        #expect(YtDlpEngine.outputLines("KDFILE /x/a.mp4") == ["KDFILE /x/a.mp4"])
        // Uygulamanın kendi mesajının içi bölünmez (başlıkta "KDPROG " geçse bile).
        let info = #"KDINFO {"title": "KDPROG nedir? KDFILE açıklaması"}"#
        #expect(YtDlpEngine.outputLines(info) == [info])
        #expect(YtDlpEngine.outputLines("") == [""])
    }

    /// Windows'taki gerçek çıktı (yt-dlp 2026.11.23, aria2c 1.37.0, Rick Astley 4K, 80.911.999 + 3.449.447 bayt).
    private static let script = #"""
    #!/bin/bash
    folder=""; prev=""
    for arg in "$@"; do
      if [[ "$prev" == "-P" && "$arg" != temp:* && -z "$folder" ]]; then folder="$arg"; fi
      prev="$arg"
    done
    echo 'KDINFO {"title": "Test Video", "filesize_approx": 84361446, "requested_formats.:.filesize": [80911999, 3449447], "requested_formats.:.filesize_approx": [80911999, 3449447]}'
    sleep 0.2
    echo '[#caef46 10MiB/77MiB(13%) CN:8 DL:20MiB]'; sleep 0.2
    echo '[#caef46 40MiB/77MiB(52%) CN:8 DL:30MiB]'; sleep 0.2
    printf '%s\n' '[#caef46 70MiB/77MiB(91%) CN:8 DL:74MiB]KDPROG {"status": "finished", "downloaded_bytes": 80911999, "total_bytes": 80911999, "speed": 49673873.7, "filename": "/tmp/kd/video.f137.mp4"}'
    sleep 0.2
    echo '[#acafac 1.0MiB/3.2MiB(30%) CN:1 DL:2.3MiB]'; sleep 0.2
    echo '[#acafac 2.3MiB/3.2MiB(70%) CN:1 DL:1.1MiB]'; sleep 0.2
    printf '%s\n' '[#acafac 2.5MiB/3.2MiB(78%) CN:1 DL:279KiB ETA:2s]KDPROG {"status": "finished", "downloaded_bytes": 3449447, "total_bytes": 3449447, "speed": 336811.0, "filename": "/tmp/kd/audio.f140.m4a"}'
    sleep 0.6
    head -c 84361446 /dev/zero > "$folder/Test Video.mp4"
    echo "KDFILE $folder/Test Video.mp4"
    exit 0
    """#

    @Test("İlerleme hiç geri gitmiyor, parçalar bitince 'işleniyor', sonra tamamlanıyor (Windows'taki hata)")
    func progressNeverGoesBack() async throws {
        TestEnvironment.prepare()
        let folder = TestEnvironment.scratch()
        let fake = folder.appendingPathComponent("yt-dlp")
        try Self.script.replacingOccurrences(of: "\n    ", with: "\n").write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        setenv("KD_YTDLP", fake.path, 1)
        defer { unsetenv("KD_YTDLP") }

        let store = DownloadStore(engine: YtDlpEngine())
        store.add([DownloadRequest(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")])
        let item = try #require(store.items.first)

        var samples: [Int64] = []
        var sawProcessing = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, item.status != .completed, !item.isFailed {
            samples.append(item.downloadedBytes)
            if item.status == .processing { sawProcessing = true }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(item.status == .completed, "durum: \(item.status)")
        let drops = zip(samples, samples.dropFirst()).filter { $1 < $0 }
        #expect(drops.isEmpty, "ilerleme geri gitti: \(drops.prefix(3))")
        #expect(samples.contains { $0 >= 80_911_999 }, "görüntü parçası sayılmadı")
        #expect(sawProcessing, "parçalar bitince 'işleniyor' görünmedi")
        #expect(item.totalBytes == 84_361_446)
        #expect(item.destination?.lastPathComponent == "Test Video.mp4")
    }
}
