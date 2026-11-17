// docs/islevler.md 2.1: kaynak onceligine gore cihaz durumu ve pil secimi.
import Foundation

/// IOBluetooth (ya da es kanali) baglanti bilgisi.
public enum ConnectionStatus: String, Sendable, Codable {
    case buMac, telefon, degil
}

/// Tek cihazin durumunu sinyallerden hesaplar. Saf deger tipi; zaman disaridan verilir.
public struct DeviceStateReducer: Sendable {
    /// Reklam bu sureden uzun gelmezse `yakinda` biter.
    public static let advertisementTimeout: TimeInterval = 10
    /// Hic sinyal yokken `bilinmiyor` durumunun suresi; sonra `bagliDegil`.
    public static let unknownGrace: TimeInterval = 60

    public private(set) var battery: BatteryReading?
    /// AAP kanalindan okunan AirPods durumu; kanal kopunca `clearAirPods()` ile silinir.
    public private(set) var airPods: AirPodsDeviceState?
    private var connection: ConnectionStatus?
    private var lastAdvertisement: Date?
    private var lastSignal: Date

    public init(startedAt: Date) {
        lastSignal = startedAt
    }

    /// Baglanti bilgisi en yuksek oncelikli kaynaktir (IOBluetooth > BLE reklam > son bilinen).
    public mutating func setConnection(_ status: ConnectionStatus, at now: Date) {
        connection = status
        lastSignal = now
    }

    public mutating func recordAdvertisement(at now: Date) {
        lastAdvertisement = now
        lastSignal = now
    }

    /// Pil kaynak onceligi: marka ozel > standart > yok. Daha dusuk oncelikli okuma yalniz
    /// mevcut okuma soluksa (30 dk) ya da yoksa kabul edilir; ayni oncelikte yeni olan kazanir.
    public mutating func updateBattery(_ reading: BatteryReading) {
        guard let current = battery else {
            if reading.source != .yok || reading.hasAnyValue { battery = reading }
            return
        }
        if reading.source.rank >= current.source.rank
            || current.isStale(at: reading.timestamp) {
            if reading.timestamp >= current.timestamp { battery = reading }
        }
    }

    /// AAP durumunu saklar ve icindeki pili ayni kaynak onceligi kuraliyla (`updateBattery`) isler.
    /// Baglanti durumuna dokunmaz: kanal baglantisi `setConnection` ile ayrica bildirilir.
    public mutating func updateAirPods(_ state: AirPodsDeviceState, at now: Date) {
        airPods = state
        if let reading = state.batteryReading(at: now) { updateBattery(reading) }
    }

    /// AAP kanali kapandi: eski durum gecersiz (ses modu / kulak algilama bilinmiyor). Pil okumasi kalir (soluklasir).
    public mutating func clearAirPods() { airPods = nil }

    public func state(at now: Date) -> DeviceState {
        let adFresh = lastAdvertisement.map { now.timeIntervalSince($0) < Self.advertisementTimeout } ?? false
        switch connection {
        case .buMac: return .bagliBuMac
        case .telefon: return .bagliTelefon
        case .degil: return adFresh ? .yakinda : .bagliDegil
        case nil:
            if adFresh { return .yakinda }
            return now.timeIntervalSince(lastSignal) >= Self.unknownGrace ? .bagliDegil : .bilinmiyor
        }
    }
}
