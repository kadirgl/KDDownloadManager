import AppKit

/// Uygulama kurulum diskinin (DMG) içinden doğrudan açıldıysa kendini Uygulamalar klasörüne taşımayı önerir.
/// Diskten çalışan kopya disk çıkarılınca kapanır, güncellemeleri kuramaz ve her seferinde diski açmak gerekir.
/// Taşınınca Uygulamalar'daki kopya açılır ve disk çıkarılır.
@MainActor
enum ApplicationsMover {
    static var applicationsFolder: URL {
        #if DEBUG
        if let folder = testFolder { return folder }
        #endif
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    #if DEBUG
    /// Geliştirme denemesi: `KD_MOVE_TEST=<klasör>` Uygulamalar yerine o klasöre taşır, yeni kopyayı açmaz (disk yine
    /// çıkarılır); `KD_MOVE_TEST_ANSWER=move|stay` soruyu sormadan cevaplar. Kurulu uygulamaya dokunulmaz.
    private static var testFolder: URL? {
        ProcessInfo.processInfo.environment["KD_MOVE_TEST"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    #endif

    private static func askToMove() -> Bool {
        #if DEBUG
        if let answer = ProcessInfo.processInfo.environment["KD_MOVE_TEST_ANSWER"] { return answer == "move" }
        #endif
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Uygulamalar klasörüne taşınsın mı?")
        alert.informativeText = String(localized: "KD Download Manager kurulum diskinin içinden açıldı. Buradan çalışırsa disk çıkarılınca kapanır ve güncellemeler kurulamaz. Uygulamalar klasörüne taşınınca oradan açılır ve disk çıkarılır.")
        alert.addButton(withTitle: String(localized: "Uygulamalar'a taşı"))
        alert.addButton(withTitle: String(localized: "Şimdilik buradan çalıştır"))
        alert.icon = NSApp.applicationIconImage
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Kurulum diskinin içinden mi açıldı: /Volumes altında, salt okunur bir diskte duran bir .app.
    /// (Yazılabilir harici diskten bilerek çalıştırılan kopyaya dokunulmaz.)
    nonisolated static func isOnDiskImage(path: String, volumeIsReadOnly: Bool) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        // ["/", "Volumes", "<disk>", …, "X.app"]
        return volumeIsReadOnly && components.count >= 4 && components[1] == "Volumes"
            && components.last?.hasSuffix(".app") == true
    }

    /// Açılışta çağrılır. Uygulama taşınıp yeniden açılacaksa true döner; o zaman açılışın geri kalanı
    /// (menü çubuğu, köprü) yapılmaz, uygulama kapanır.
    static func offerIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL
        let values = try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey])
        guard isOnDiskImage(path: source.path, volumeIsReadOnly: values?.volumeIsReadOnly ?? false) else { return false }

        guard askToMove() else { return false }

        let destination = applicationsFolder.appendingPathComponent(source.lastPathComponent)
        do {
            try install(source, at: destination)
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = String(localized: "Uygulamalar klasörüne taşınamadı")
            failure.informativeText = String(localized: "\(error.localizedDescription)\n\nKD Download Manager'ı açık penceredeki Uygulamalar klasörünün üstüne sürükleyin.")
            failure.runModal()
            return false
        }
        relaunch(destination, ejecting: values?.volume ?? source.deletingLastPathComponent())
        return true
    }

    /// Uygulamalar'da eski bir kopya varsa (açıksa önce kapatılır) Çöp Sepeti'ne gider, yerine bu kopya konur.
    private static func install(_ source: URL, at destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            where app.bundleURL?.standardizedFileURL == destination.standardizedFileURL {
                app.terminate()
                let deadline = Date().addingTimeInterval(5)
                while !app.isTerminated, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
                if !app.isTerminated { app.forceTerminate() }
            }
            try manager.trashItem(at: destination, resultingItemURL: nil)
        }
        try manager.copyItem(at: source, to: destination)
    }

    /// Bu süreç bitince Uygulamalar'daki kopyayı açan ve diski çıkaran küçük bir betik başlatır, sonra kapanır.
    /// Betik /bin/sh'tan çalıştığı için diski meşgul etmez.
    private static func relaunch(_ app: URL, ejecting volume: URL) {
        let script = """
        pid="$1"; app="$2"; volume="$3"
        i=0
        while kill -0 "$pid" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
        [ "$4" = "open" ] && open "$app"
        sleep 1
        hdiutil detach -quiet "$volume" || hdiutil detach -quiet -force "$volume"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        var reopen = true
        #if DEBUG
        if testFolder != nil { reopen = false }
        #endif
        process.arguments = ["-c", script, "kd-move", String(ProcessInfo.processInfo.processIdentifier), app.path, volume.path,
                             reopen ? "open" : "stay"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        NSApp.terminate(nil)
    }
}
