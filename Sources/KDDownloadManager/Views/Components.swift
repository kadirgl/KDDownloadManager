import SwiftUI

/// Phosphor ikonunu sabit boyutta çizer; rengi `foregroundStyle` ile verilir.
struct PhIcon: View {
    let icon: Ph
    var weight: Ph.IconWeight = .regular
    var size: CGFloat = 20

    init(_ icon: Ph, weight: Ph.IconWeight = .regular, size: CGFloat = 20) {
        self.icon = icon
        self.weight = weight
        self.size = size
    }

    var body: some View {
        icon.weight(weight)
            .frame(width: size, height: size)
    }
}

/// Satırlardaki ve başlıktaki yuvarlak, üzerine gelince hafif vurgulanan ikon butonları.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(6)
                .background(Circle().fill(Theme.mutedFill.opacity(hovering ? 1 : 0)))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

/// Turuncu (seçili) veya gri kapsül buton.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    /// Seçili değilken arka plan; gri zemin üstündeki çiplerde beyaz kullanılıyor.
    var inactiveFill: Color = Theme.mutedFill
    var horizontalPadding: CGFloat = 14
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        PillBody(style: self, configuration: configuration)
    }

    /// `isEnabled` ortam değeri ButtonStyle'da okunamadığı için ayrı görünüm.
    private struct PillBody: View {
        let style: PillButtonStyle
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: style.fontSize, weight: .medium))
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, 7)
                .foregroundStyle(style.prominent ? Color.white : Theme.primaryText)
                .background(Capsule().fill(style.prominent ? Theme.accent : style.inactiveFill))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
                .contentShape(Capsule())
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: value > 0 ? max(geo.size.width * value, 6) : 0)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// Satırın solundaki turuncu dosya kutusu.
struct FileTile: View {
    let icon: Ph

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.accent)
            .frame(width: 46, height: 46)
            .overlay(PhIcon(icon, weight: .fill, size: 22).foregroundStyle(.white))
    }
}

struct SourceBadge: View {
    let source: DownloadSource

    var body: some View {
        HStack(spacing: 4) {
            PhIcon(icon, weight: .bold, size: 12)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(Theme.accent)
        .background(Capsule().fill(Theme.accent.opacity(0.12)))
    }

    private var icon: Ph {
        switch source {
        case .direct: .downloadSimple
        case .video: .filmStrip
        case .torrent: .magnet
        }
    }

    private var title: String {
        switch source {
        case .direct: "Dosya"
        case .video: "Video"
        case .torrent: "Torrent"
        }
    }
}
