// QCY kontrol kanali sahipligi karari (saf mantik). Kulaklik tek LE baglantisi kabul eder:
// - Ilk yoneten cihaz sahip kalir; diger cihaz zorla almaz, otomatik GATT denemez (relay kullanir).
// - Sahiplik yalniz kullanici dugmesiyle ya da sahibin kalici kopmasiyla el degistirir.
// - Kimse sahip degilken esit zamanlamada Mac onceliklidir; telefon oturumu acik ama sahip degilse Mac alabilir.
import Foundation

public enum ControlOwner: Sendable, Equatable { case none, mac, phone }

public enum ControlOwnership {
    /// `claimant` sahiplik istiyor/bildiriyor. `userInitiated`: kullanici dugmeye basti.
    public static func resolve(current: ControlOwner, claimant: ControlOwner, userInitiated: Bool) -> ControlOwner {
        guard claimant != .none else { return current }
        switch current {
        case .none: return claimant
        case claimant: return current
        default: return userInitiated ? claimant : current
        }
    }

    /// Ayni anda iki taraf da sahip bildirdi (kimse sahip degildi): Mac onceliklidir.
    public static func simultaneousClaim() -> ControlOwner { .mac }

    /// Sahibin baglantisi / oturumu kalici koptu: sahip degilse etkilenmez.
    public static func afterLoss(current: ControlOwner, lost: ControlOwner) -> ControlOwner {
        current == lost ? .none : current
    }

    /// Mac otomatik (kullanicisiz) dogrudan GATT deneyebilir mi? Telefon sahipken hayir.
    public static func macMayAutoConnect(current: ControlOwner) -> Bool { current != .phone }
}
