// docs/islevler.md 2.5: dusuk pil bildirimi, histerezisli.
import Foundation

public struct LowBatteryAlert: Equatable, Sendable {
    public let deviceID: String
    public let channel: BatteryChannel
    public let percent: Int
}

/// Sol / sag / kutu (ve tek degerli genel pil) ayri izlenir.
/// <= %20 ilk gorulunce bir kez uyarir; %25'in ustune cikmadan tekrar uyarmaz; sarjdayken uyarmaz.
public struct LowBatteryMonitor: Sendable {
    public static let alertThreshold = 20
    public static let rearmThreshold = 25

    private struct Key: Hashable { let deviceID: String; let channel: BatteryChannel }
    private var disarmed: Set<Key> = []

    public init() {}

    public mutating func observe(deviceID: String, reading: BatteryReading, at now: Date) -> [LowBatteryAlert] {
        guard !reading.isStale(at: now) else { return [] }
        var alerts: [LowBatteryAlert] = []
        for channel in BatteryChannel.allCases {
            guard let level = reading.level(channel) else { continue }
            let key = Key(deviceID: deviceID, channel: channel)
            if level > Self.rearmThreshold {
                disarmed.remove(key)
            } else if level <= Self.alertThreshold, !reading.isCharging(channel), !disarmed.contains(key) {
                disarmed.insert(key)
                alerts.append(LowBatteryAlert(deviceID: deviceID, channel: channel, percent: level))
            }
        }
        return alerts
    }

    /// Cihaz unutulunca gecmisi temizler.
    public mutating func reset(deviceID: String) {
        disarmed = disarmed.filter { $0.deviceID != deviceID }
    }
}
