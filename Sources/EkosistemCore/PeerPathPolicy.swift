// Telefon kanali yolu secimi (saf mantik): Wi-Fi (TCP/Bonjour) oncelikli, Bluetooth RFCOMM yedek.
// Aginiz yok: zaman ve durum girer, eylem cikar. Ayni anda iki oturum acilmaz.
import Foundation

public enum PeerPath: String, Sendable, Equatable {
    case wifi, bluetooth

    /// RFCOMM akisinda dosya aktarimi kapali (dusuk bant); diger her sey calisir.
    public var allowsFileTransfer: Bool { self == .wifi }
}

public enum PeerPathAction: Equatable, Sendable {
    case none
    /// SDP sorgusu + RFCOMM baglantisi baslat.
    case tryBluetooth
    /// Wi-Fi geldi: Bluetooth oturumunu / denemesini kapat.
    case dropBluetooth
}

public struct PeerPathPolicy: Sendable {
    /// Wi-Fi'nin gelmesi icin beklenen sure (baslangic ve Wi-Fi kopmasindan sonra).
    public static let wifiGrace: TimeInterval = 10
    /// Ardisik RFCOMM basarisizliklarinda bekleme (sn); son deger sabit kalir. Surekli SDP / sayfalama yapilmaz.
    public static let delays: [TimeInterval] = [15, 45, 120, 300]
    /// Bu kadar suredir acik kalan Bluetooth oturumu "kararli" sayilir (sayac sifirlanir).
    public static let stableAfter: TimeInterval = 60

    public private(set) var failures = 0
    private var wifiAbsentSince: Date?
    private var nextAttempt: Date?
    private var wasWifiActive = false

    public init(now: Date) { wifiAbsentSince = now }

    /// Periyodik cagri. `bluetoothBusy`: RFCOMM oturumu ya da denemesi suruyor. `canTry`: Bluetooth acik,
    /// telefon adayi var, kanal etkin.
    public mutating func evaluate(now: Date, wifiActive: Bool, bluetoothBusy: Bool, canTry: Bool) -> PeerPathAction {
        if wifiActive {
            wasWifiActive = true
            wifiAbsentSince = nil
            failures = 0; nextAttempt = nil
            return bluetoothBusy ? .dropBluetooth : .none
        }
        if wasWifiActive || wifiAbsentSince == nil { wifiAbsentSince = now; wasWifiActive = false }
        guard !bluetoothBusy, canTry, let since = wifiAbsentSince else { return .none }
        guard now.timeIntervalSince(since) >= Self.wifiGrace else { return .none }
        if let nextAttempt, now < nextAttempt { return .none }
        return .tryBluetooth
    }

    /// Bluetooth denemesi basarisiz oldu ya da oturum bitti. `establishedAt`: oturum kurulmus idiyse an.
    /// Donus: bir sonraki deneme icin bekleme (sn).
    @discardableResult
    public mutating func bluetoothEnded(now: Date, establishedAt: Date?, jitter: Double = 0) -> TimeInterval {
        if let establishedAt, now.timeIntervalSince(establishedAt) >= Self.stableAfter { failures = 0 }
        let delay = Self.delays[min(failures, Self.delays.count - 1)] * (1 + max(jitter, 0))
        failures += 1
        nextAttempt = now.addingTimeInterval(delay)
        return delay
    }

    /// Kullanici "Yenile" dedi / ayar degisti.
    public mutating func reset(now: Date) {
        failures = 0; nextAttempt = nil
        wifiAbsentSince = now
    }
}
