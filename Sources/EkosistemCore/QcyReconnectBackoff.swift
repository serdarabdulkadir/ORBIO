// QCY GATT yeniden baglanma geri cekilmesi (saf mantik). Baglanti kisa surede tekrar kopuyorsa (iki merkez
// cakismasi, zayif sinyal) deneme sayaci SIFIRLANMAZ; yalnizca `stableAfter` kadar hazir kalan baglanti sifirlar.
import Foundation

public struct QcyReconnectBackoff: Sendable {
    /// Gecikmeler (sn); son deger (3 dk) sabit kalir; hizli buyur ki telefon kanali tutarken 2.4 GHz'te surekli deneme olmasin.
    public static let delays: [TimeInterval] = [5, 15, 45, 180]
    /// Bu kadar suredir hazir olan baglanti "kararli" sayilir.
    public static let stableAfter: TimeInterval = 30

    public private(set) var failures = 0

    public init() {}

    /// Basarisizlik / kopma: siradaki bekleme (sn). `readySince`: kanal hazir oldugu an (hic hazir olmadiysa nil).
    /// `jitter`: 0...0.2 gibi kesir; iki merkezin ayni anda yeniden denemesini dagitir.
    public mutating func failed(now: Date, readySince: Date?, jitter: Double = 0) -> TimeInterval {
        if let readySince, now.timeIntervalSince(readySince) >= Self.stableAfter { failures = 0 }
        let delay = Self.delays[min(failures, Self.delays.count - 1)]
        failures += 1
        return delay * (1 + max(jitter, 0))
    }

    /// Kullanici "Yenile" dedi ya da kanal sahipligi degisti.
    public mutating func reset() { failures = 0 }
}
