import Darwin

/// Bir süreci, başlattığı alt süreçlerle (yt-dlp'nin aria2c ve ffmpeg'i) birlikte durdurur.
/// Sadece ana sürece sinyal göndermek yetmiyor: yt-dlp kapanınca aria2c sahipsiz kalıp inmeye,
/// ffmpeg dosyaya yazmaya devam ediyordu.
enum ProcessTree {
    /// Sinyal gönderilen bütün süreçleri döndürür (ana süreç dahil).
    @discardableResult
    static func terminate(_ pid: pid_t, signal: Int32 = SIGTERM) -> [pid_t] {
        // Önce hepsini topla, sonra en alttakilerden başlayarak durdur; ebeveyn önce ölürse çocuklar
        // launchd'ye geçer ve artık bulunamaz.
        let all = [pid] + descendants(of: pid)
        for process in all.reversed() {
            kill(process, signal)
        }
        return all
    }

    /// aria2c SIGTERM'de bağlantılarını toparlayıp kontrol dosyasını yazarak kapanıyor; bu bazen
    /// saniyeler sürüyor. Süre dolunca hâlâ yaşayanlar zorla kapatılır.
    static func killSurvivors(_ pids: [pid_t]) {
        for process in pids where kill(process, 0) == 0 {
            kill(process, SIGKILL)
        }
    }

    /// Bütün alt süreçler, ebeveynden çocuğa doğru sırayla.
    static func descendants(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue = [pid]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let count = proc_listchildpids(current, nil, 0)
            guard count > 0 else { continue }
            var children = [pid_t](repeating: 0, count: Int(count) + 8)
            let found = children.withUnsafeMutableBytes { buffer in
                proc_listchildpids(current, buffer.baseAddress, Int32(buffer.count))
            }
            let valid = children.prefix(Int(max(found, 0))).filter { $0 > 0 }
            result += valid
            queue += valid
        }
        return result
    }
}
