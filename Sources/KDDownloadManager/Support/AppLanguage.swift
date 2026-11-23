import AppKit

/// Arayüz dili. Metinler Türkçe yazılı (geliştirme dili); İngilizcesi `Resources/Localizable.xcstrings`
/// dosyasından derlenen `en.lproj` ile gelir. Seçim, macOS'un uygulamaya özel dil ayarıyla aynı yolu
/// kullanır (uygulamanın kendi alanındaki `AppleLanguages`); Sistem Ayarları > Genel > Dil ve Bölge >
/// Uygulamalar'dan yapılan seçim de burada görünür. Dil, uygulama yeniden açılınca değişir.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, turkish = "tr", english = "en"

    var id: Self { self }

    /// Dil adları her zaman kendi dilinde yazılır; "Sistem" ise arayüzün dilinde.
    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    private static let key = "AppleLanguages"

    /// Uygulamanın kendi ayarlarında kayıtlı seçim (komut satırındaki `-AppleLanguages` sayılmaz).
    static var stored: AppLanguage {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let languages = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String]
        guard let first = languages?.first else { return .system }
        return first.hasPrefix("tr") ? .turkish : first.hasPrefix("en") ? .english : .system
    }

    /// Uygulama açılırken kayıtlı olan seçim; Ayarlar bundan farklıysa yeniden başlatmayı önerir.
    static let launchChoice = stored

    static func store(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }

    /// Şu an gösterilen dil ("tr" ya da "en"). Çeviri dosyaları pakette yoksa (derlenmemiş geliştirme
    /// sürümü) metinler Türkçe kalır; biçimler de ona uysun.
    static let current: String = {
        guard Bundle.main.localizations.contains("en") else { return "tr" }
        return Bundle.main.preferredLocalizations.first == "en" ? "en" : "tr"
    }()

    /// Seçilen dili `current` ile aynı olan yerel ayar; bölge (ondalık ayracı, saat biçimi) sistemden.
    static let locale: Locale = {
        let system = Locale.current
        if system.language.languageCode?.identifier == current { return system }
        var components = Locale.Components(locale: system)
        components.languageComponents = Locale.Language.Components(languageCode: .init(current))
        return Locale(components: components)
    }()

    /// Yüzde: Türkçede "%45", İngilizcede "45%". İşaretin yeri bölgeye değil dile göre (İngilizce arayüz ve
    /// Türkiye bölgesinde de "45%").
    static func percent(_ fraction: Double) -> String {
        ((fraction * 100).rounded(.down) / 100)
            .formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: current)))
    }

    /// Göreli zaman ("2 saat önce" / "2 hours ago").
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(locale))
    }

    /// Dil değişikliğinin uygulanması için uygulamayı kapatıp yeniden açar.
    @MainActor
    static func relaunch() {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { NSApp.terminate(nil); return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Bu süreç tamamen kapanınca (indirme listesi kaydedildikten sonra) yeni kopyayı açar.
        script.arguments = ["-c", "i=0; while kill -0 \(pid) 2>/dev/null && [ $i -lt 300 ]; do sleep 0.2; i=$((i+1)); done; /usr/bin/open \"$0\"",
                            app.path]
        try? script.run()
        NSApp.terminate(nil)
    }
}
