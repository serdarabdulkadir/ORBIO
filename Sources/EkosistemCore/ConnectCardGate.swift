// "Baglandi" kisa karti kapisi: kulaklik BU MAC'E baglandigi an gosterilir. Saf deger tipi.
import Foundation

public struct ConnectCardGate: Sendable {
    /// Uygulama acilisindan sonra bu sure icinde gosterilmez (ilk durum oturana kadar).
    public static let startupGrace: TimeInterval = 5
    /// Ayni cihaz icin iki kart arasi en az sure (kopup baglanan cihazda tekrar etmesin).
    public static let cooldown: TimeInterval = 10
    /// Kart kendiliginden bu sure sonra kapanir.
    public static let visibleDuration: TimeInterval = 3

    private var previous: [String: DeviceState] = [:]
    private var lastShown: [String: Date] = [:]
    private let startedAt: Date

    public init(startedAt: Date) { self.startedAt = startedAt }

    /// Cihazin guncel durumunu bildirir; kart gosterilmeli mi?
    /// Yalniz `bagliDegil` / `yakinda` -> `bagliBuMac` gecisinde true. Ilk gorulen durum (uygulama acilisinda
    /// zaten bagli olan cihaz) ve `bilinmiyor` / `bagliTelefon` kaynakli gecisler gostermez.
    public mutating func observe(deviceID: String, state: DeviceState, proximityEnabled: Bool, silent: Bool,
                                 screenLocked: Bool, at now: Date) -> Bool {
        let before = previous[deviceID]
        previous[deviceID] = state
        guard state == .bagliBuMac, let before, before == .bagliDegil || before == .yakinda else { return false }
        guard proximityEnabled, !silent, !screenLocked else { return false }
        guard now.timeIntervalSince(startedAt) >= Self.startupGrace else { return false }
        if let last = lastShown[deviceID], now.timeIntervalSince(last) < Self.cooldown { return false }
        lastShown[deviceID] = now
        return true
    }

    public mutating func forget(deviceID: String) {
        previous[deviceID] = nil
        lastShown[deviceID] = nil
    }
}
