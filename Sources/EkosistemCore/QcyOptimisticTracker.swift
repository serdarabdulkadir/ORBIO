// Iyimser guncelleme + zaman asimli dogrulama (saf mantik). Yazilan komut arayuzde hemen gorunur, ama cihazin
// kendi bildirimi / geri okumasi gelene dek "kesin" sayilmaz: onaylanirsa kayit silinir, `timeout` icinde onaylanmazsa
// `expire` komutu doner (arayuz cihazin gercek durumuna doner ve uyarir). Beklerken gelen ESKI durum bildirimi
// arayuzu geri cevirmez (`reconcile` bekleyen komutu uzerine uygular).
import Foundation

public struct QcyOptimisticTracker: Sendable {
    public static let defaultTimeout: TimeInterval = 4

    private struct Entry: Sendable {
        var command: QcyCommand
        var deadline: Date
    }

    /// Opcode -> bekleyen komut; ayni opcode'a yeni yazma onceki beklemeyi degistirir (son yazilan kazanir).
    private var entries: [UInt8: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var pendingCount: Int { entries.count }

    public mutating func begin(_ command: QcyCommand, now: Date, timeout: TimeInterval = defaultTimeout) {
        entries[command.readbackOpcode] = Entry(command: command, deadline: now.addingTimeInterval(timeout))
    }

    /// Cihazdan gelen durum: onaylananlar silinir; zamani gecmemis bekleyenler gosterilecek duruma uygulanir.
    public mutating func reconcile(device: QcyDeviceState, now: Date) -> QcyDeviceState {
        var shown = device
        for (opcode, entry) in entries {
            if entry.command.isSatisfied(by: device) {
                entries[opcode] = nil
            } else if now < entry.deadline {
                shown = shown.applying(entry.command)
            }
        }
        return shown
    }

    /// Zamani dolup onaylanmayanlar (silinir). Arayuz cihaz durumuna doner.
    public mutating func expire(now: Date) -> [QcyCommand] {
        let dead = entries.filter { now >= $0.value.deadline }
        for key in dead.keys { entries[key] = nil }
        return dead.values.map(\.command)
    }

    /// Kanal koptu: bekleyenler gecersiz.
    public mutating func removeAll() { entries.removeAll() }
}
