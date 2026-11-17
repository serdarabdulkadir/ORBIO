// docs/islevler.md 2.4: yaklasma pil kartinin gosterim kapisi. Saf deger tipi.
import Foundation

public struct CardContent: Equatable, Sendable {
    public enum Source: Sendable { case reklam, sistem }
    public let deviceID: String
    public let battery: BatteryReading
    public let source: Source

    public init(deviceID: String, battery: BatteryReading, source: Source) {
        self.deviceID = deviceID; self.battery = battery; self.source = source
    }
}

public enum CardSuppression: Equatable, Sendable {
    case ekranKilitli, yakinZamandaGosterildi, pilYok
    /// Kulaklik zaten bu Mac'e bagli: pil karti gereksiz.
    case zatenBagli
}

public enum CardDecision: Equatable, Sendable {
    /// Henuz yeterli paket yok (ya da sinyal zayif).
    case bekle
    case goster(CardContent)
    case bastir(CardSuppression)
}

public struct ProximityCardGate: Sendable {
    /// Bu degerden guclu (daha buyuk) RSSI gerekir.
    public static let rssiThreshold = -55
    public static let requiredConsecutivePackets = 2
    public static let cooldown: TimeInterval = 60
    public static let visibleDuration: TimeInterval = 8

    /// Cihaz basina esik (simdilik hepsi ayni; olcume gore ayrilabilir).
    public static func threshold(for deviceID: String) -> Int { rssiThreshold }

    private var consecutive: [String: Int] = [:]
    private var lastShown: [String: Date] = [:]
    private var visible: (deviceID: String, since: Date)?

    public init() {}

    public var visibleDeviceID: String? { visible?.deviceID }

    /// Bir "yakin" reklam paketini degerlendirir.
    /// - Parameters:
    ///   - decoded: reklamdan cozulen pil; nil ise `systemBattery`'ye dusulur (2.4 adim 4).
    ///   - systemBattery: sistemin bildirdigi pil degeri; o da yoksa kart gosterilmez.
    ///   - alreadyConnected: cihaz zaten bu Mac'e bagliysa kart gosterilmez (sayac ve tekrar engeli etkilenmez).
    public mutating func consider(deviceID: String, rssi: Int, decoded: BatteryReading?, systemBattery: BatteryReading?,
                                  screenLocked: Bool, alreadyConnected: Bool = false, at now: Date) -> CardDecision {
        guard rssi > Self.rssiThreshold else {
            consecutive[deviceID] = 0
            return .bekle
        }
        // "Ust uste": baska cihazin paketi araya girerse onun sayaci sifirlanir.
        for other in consecutive.keys where other != deviceID { consecutive[other] = 0 }
        let count = (consecutive[deviceID] ?? 0) + 1
        consecutive[deviceID] = count
        guard count >= Self.requiredConsecutivePackets else { return .bekle }
        if screenLocked { return .bastir(.ekranKilitli) }
        if alreadyConnected { return .bastir(.zatenBagli) }
        if let last = lastShown[deviceID], now.timeIntervalSince(last) < Self.cooldown {
            return .bastir(.yakinZamandaGosterildi)
        }
        let content: CardContent
        if let decoded, decoded.hasAnyValue {
            content = CardContent(deviceID: deviceID, battery: decoded, source: .reklam)
        } else if let systemBattery, systemBattery.hasAnyValue {
            content = CardContent(deviceID: deviceID, battery: systemBattery, source: .sistem)
        } else {
            return .bastir(.pilYok)
        }
        lastShown[deviceID] = now
        visible = (deviceID, now)
        consecutive[deviceID] = 0
        return .goster(content)
    }

    /// Kart 8 sn doldu mu? Doldiysa gorunurlugu kapatir ve true doner.
    public mutating func dismissIfExpired(at now: Date) -> Bool {
        guard let v = visible, now.timeIntervalSince(v.since) >= Self.visibleDuration else { return false }
        visible = nil
        return true
    }

    /// Kapak kapandi / ekran kilitlendi / kullanici kapatti: kart gorunuyorsa kapatir.
    public mutating func dismiss() -> Bool {
        defer { visible = nil }
        return visible != nil
    }
}
