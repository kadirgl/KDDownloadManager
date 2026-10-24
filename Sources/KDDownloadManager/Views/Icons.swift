import SwiftUI

/// Uygulamada kullanılan Phosphor ikonları (https://phosphoricons.com, MIT — Resources/Phosphor-LICENSE.txt).
/// Paketin tamamı ~1.500 ikon × 6 ağırlık (~84 MB) taşıdığı için yalnızca kullandığımız
/// ikon/ağırlık çiftleri Resources/Icons.xcassets'te duruyor. Yeni bir çift gerekirse
/// phosphor-icons/core'dan SVG'sini aynı adla (`<ikon>` ya da `<ikon>-<ağırlık>`) bir
/// template imageset olarak ekleyin; eksik çift çizilmez, konsola "No image named" düşer.
enum Ph: String {
    case appWindow = "app-window"
    case arrowCircleDown = "arrow-circle-down"
    case arrowClockwise = "arrow-clockwise"
    case arrowDown = "arrow-down"
    case caretLeft = "caret-left"
    case check
    case clipboard
    case downloadSimple = "download-simple"
    case file
    case fileZip = "file-zip"
    case filmStrip = "film-strip"
    case flag
    case folder
    case folderOpen = "folder-open"
    case gauge
    case gear
    case link
    case magnet
    case musicNotes = "music-notes"
    case pauseCircle = "pause-circle"
    case play
    case playCircle = "play-circle"
    case power
    case xCircle = "x-circle"

    enum IconWeight: String {
        case regular
        case light
        case bold
        case fill
    }

    func weight(_ weight: IconWeight) -> Image {
        let name = weight == .regular ? rawValue : "\(rawValue)-\(weight.rawValue)"
        return Image(name, bundle: .module)
            .interpolation(.medium)
            .resizable()
    }
}
