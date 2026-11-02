import SwiftUI
import AppKit

// Liquid Glass bileşenleri: cam kart, cam ikon buton, ana (vurgu) buton, kategori ikonu, stepper,
// bölüm etiketi ve ilerleme çubuğu. Pencerenin bulanıklığını sistem çiziyor (StatusItemController);
// kartlar onun üstünde yarı saydam katmanlar.

// MARK: - Cam yüzeyler

extension View {
    /// Kart, sekme rayı ve ikon butonların camı: yarı saydam zemin, çevrede ince çizgi, üstte ışık.
    func glassCard(radius: CGFloat = Theme.cardRadius) -> some View {
        background(GlassShape(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), strength: .regular))
    }

    /// Yüzen bar ve küçük butonların daha belirgin camı (altındaki içeriği bulanıklaştırır).
    func strongGlass<S: InsettableShape>(_ shape: S) -> some View {
        background(GlassShape(shape: shape, strength: .strong))
    }
}

private struct GlassShape<S: InsettableShape>: View {
    enum Strength { case regular, strong }

    let shape: S
    let strength: Strength
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if strength == .strong {
                // Altından kayan liste okunmasın diye gerçek bulanıklık.
                if reduceTransparency {
                    shape.fill(Theme.windowSolid)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            shape.fill(strength == .strong ? Theme.strongGlass : Theme.glass)
            shape.strokeBorder(strength == .strong ? Theme.strongGlassEdge : Theme.glassEdge, lineWidth: 1)
            // Üst kenardaki ışık çizgisi.
            shape.strokeBorder(
                LinearGradient(
                    colors: [strength == .strong ? Theme.strongGlassHighlight : Theme.glassHighlight, .clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.18)
                ),
                lineWidth: 1
            )
        }
        .compositingGroup()
        .shadow(color: strength == .strong ? Theme.shadow : .clear, radius: 15, y: 10)
    }
}

// MARK: - Butonlar

/// Basılınca %94'e küçülme, üstüne gelince hafif aydınlanma, pasifken %35 — tüm butonlarda ortak.
private struct InteractionModifier: ViewModifier {
    let isPressed: Bool
    @Binding var hovering: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.94 : 1)
            .brightness(hovering && isEnabled ? 0.04 : 0)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .onHover { hovering = $0 }
    }
}

/// Cam daire ikon buton (link, ayarlar, klasör, sil, duraklat). Etiket bir SF Symbol olmalı.
struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 40
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(style: self, configuration: configuration)
    }

    private struct StyledBody: View {
        let style: GlassIconButtonStyle
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: style.size * 0.36, weight: .semibold))
                .foregroundStyle(style.tint ?? Theme.primaryText)
                .frame(width: style.size, height: style.size)
                .strongGlass(Circle())
                .contentShape(Circle())
                .modifier(InteractionModifier(isPressed: configuration.isPressed, hovering: $hovering))
        }
    }
}

/// Turuncu (vurgu) kapsül: Link ekle, İndir, Kurulumu başlat. Altında vurgu renginde parıltı.
struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(style: self, configuration: configuration)
    }

    private struct StyledBody: View {
        let style: AccentButtonStyle
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: style.fontSize, weight: .semibold))
                .padding(.horizontal, style.height * 0.5)
                .frame(minHeight: style.height)
                .foregroundStyle(Theme.onAccent)
                .background(
                    Capsule()
                        .fill(Theme.accent)
                        .overlay(Capsule().strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center),
                            lineWidth: 1
                        ))
                        .shadow(color: Theme.accentGlow, radius: 10, y: 6)
                )
                .contentShape(Capsule())
                .modifier(InteractionModifier(isPressed: configuration.isPressed, hovering: $hovering))
        }
    }
}

/// Cam kapsül (ikincil): Değiştir, Denetle, Kopyala, İptal.
struct GlassCapsuleButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(style: self, configuration: configuration)
    }

    private struct StyledBody: View {
        let style: GlassCapsuleButtonStyle
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: style.fontSize, weight: .semibold))
                .padding(.horizontal, style.height * 0.45)
                .frame(minHeight: style.height)
                .foregroundStyle(Theme.primaryText)
                .strongGlass(Capsule())
                .contentShape(Capsule())
                .modifier(InteractionModifier(isPressed: configuration.isPressed, hovering: $hovering))
        }
    }
}

/// Menü ve listelerdeki satır butonu: üstüne gelince cam vurgu.
struct MenuRowButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(selected: selected, configuration: configuration)
    }

    private struct StyledBody: View {
        let selected: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.badge.opacity(selected ? 1 : hovering ? 0.7 : 0))
                )
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Kategori ikonu

/// Renkli kategori kutusu: yukarıdan aşağı iki renkli geçiş, üstte parlama ve ışık çizgisi, beyaz sembol.
struct CategoryIcon: View {
    let category: DownloadCategory
    var size: CGFloat = 52

    var body: some View {
        let radius = size * 0.225
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [category.topColor, category.bottomColor], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: size * 0.55)
                    .clipShape(shape)
            }
            .overlay(shape.strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            // Üst kenardaki 1 pt ışık çizgisi.
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.06)),
                lineWidth: 1
            ))
            .overlay(
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 0.6, y: 0.6)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Küçük parçalar

/// Bölüm etiketi: 11 pt, kalın, büyük harf, harf aralığı 0,8.
struct SectionLabel: View {
    let title: String

    var body: some View {
        // Türkçe kurala göre büyüt: "indirici" → "İNDİRİCİ" (textCase sistemin diline göre "INDIRICI" yapıyor).
        Text(title.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Sekme ve butonların yanındaki sayı rozeti.
struct CountBadge: View {
    let count: Int
    var onAccent = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(Capsule().fill(onAccent ? Color.black.opacity(0.14) : Theme.badge))
    }
}

/// Klavye tuşu görünümü (⌘, V).
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold))
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.badge))
    }
}

/// Kartın içindeki satırları ayıran ince çizgi.
struct GlassDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}

/// İlerleme çubuğu. Animasyonsuz: indirmeler saniyede iki kez ilerliyor, her seferinde başlayan animasyon
/// çubukları neredeyse sürekli ekran yenileme hızında (gölgeli parlamayla) yeniden çizdiriyordu.
struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.accent
    /// Devam eden indirmede çubuğun hafif parlaması (gölge yerine ucuz bir renk geçişi).
    var glows = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(glows
                          ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(tint))
                    .frame(width: value > 0 ? max(geo.size.width * value, 5) : 0)
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityValue("%\(Int(value * 100))")
    }
}

/// − / değer / + cam kapsülü (sistem Stepper okları yerine).
struct GlassStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
                .accessibilityLabel("\(label) azalt")
            Text(format(value))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 28)
                .contentTransition(.numericText())
            button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
                .accessibilityLabel("\(label) artır")
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .strongGlass(Capsule())
        .animation(.snappy, value: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// Cam rayın içinde kayan hapla seçim (tema seçici).
struct GlassSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: selection == option.value ? .semibold : .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if selection == option.value {
                                Capsule()
                                    .fill(Theme.selectedPill)
                                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(3)
        .glassCard(radius: 16)
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

/// Başlık satırı: geri butonu (varsa), başlık ve sağdaki cam ikon butonlar.
struct PanelHeader<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(GlassIconButtonStyle(size: 36))
                .keyboardShortcut(.cancelAction)
                .help("Geri")
                .accessibilityLabel("Geri")
            }
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}
