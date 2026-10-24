import Foundation

/// Uygulamaya dışarıdan (panel ya da Chrome eklentisi) gelen indirme isteği.
/// Tarayıcıdan gelenlerde, giriş gerektiren indirmeler için istek bilgileri de bulunur.
struct DownloadRequest: Decodable, Sendable {
    var url: String
    /// Chrome'un sunucudan öğrendiği dosya adı; sadece aria2 kendi adını bulana kadar gösterilir.
    var filename: String?
    var referrer: String?
    var userAgent: String?
    /// "ad=değer; ad2=değer2" biçiminde çerez başlığı.
    var cookies: String?
}
