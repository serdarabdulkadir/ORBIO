// BLE tarama zamanlayicisi (saf mantik): surekli tarama yerine kisa pencereler.
// 2.4 GHz'te surekli tarama A2DP akisini bozar (cizirti); bu yuzden tarama yalniz gerektiginde ve pencereli acilir.
import Foundation

public enum ScanProfile: Equatable, Sendable {
    /// Tarama gerekmiyor (kontrol kanali hazir ve pil GATT'ten geliyor, AirPods yok).
    case off
    /// Kanal hazir ama pil kaynagi GATT degil: seyrek pencere.
    case sparse
    /// Cihaz gorunmuyor / bagli degil ya da yaklasma karti icin Apple cihazi var.
    case active

    /// Talepten profil secimi. `appleKnown`: AirPods yaklasma karti reklamlari icin.
    public static func resolve(qcyNeedsAdvert: Bool, qcyReadyWithoutGattBattery: Bool, appleKnown: Bool) -> ScanProfile {
        if qcyNeedsAdvert || appleKnown { return .active }
        if qcyReadyWithoutGattBattery { return .sparse }
        return .off
    }

    /// (acik sn, kapali sn)
    var windows: (on: TimeInterval, off: TimeInterval)? {
        switch self {
        case .off: nil
        case .sparse: (2, 60)
        case .active: (4, 20)
        }
    }

    /// Tekrarlayan paketler yalniz yaklasma karti (ust uste 2 paket) icin gerekir: etkin pencerede acik.
    public var allowsDuplicates: Bool { self == .active }
}

public struct ScanScheduler: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case start(allowDuplicates: Bool)
        case stop
    }

    private enum Phase: Equatable { case idle, scanning(until: Date), cooling(since: Date, until: Date) }
    private var phase: Phase = .idle
    private var lastProfile: ScanProfile = .off

    public init() {}

    public var isScanning: Bool { if case .scanning = phase { true } else { false } }

    /// Saniyede bir cagrilir. Profil `off` ise hemen durdurur; `idle` iken talep gelirse hemen pencere acar.
    public mutating func tick(now: Date, profile: ScanProfile) -> Action {
        defer { lastProfile = profile }
        guard let w = profile.windows else {
            let was = isScanning
            phase = .idle
            return was ? .stop : .none
        }
        switch phase {
        case .idle:
            phase = .scanning(until: now.addingTimeInterval(w.on))
            return .start(allowDuplicates: profile.allowsDuplicates)
        case .scanning(let until):
            if profile != lastProfile {
                // Profil degisti (seyrek <-> etkin): yeni sureyle devam, tekrar-paket ayari guncellenir.
                phase = .scanning(until: min(until, now.addingTimeInterval(w.on)))
                return .start(allowDuplicates: profile.allowsDuplicates)
            }
            if now >= until {
                phase = .cooling(since: now, until: now.addingTimeInterval(w.off))
                return .stop
            }
            return .none
        case .cooling(let since, let until):
            // Kapali sure profile gore kisalabilir (seyrek -> etkin gecisinde en cok 20 sn).
            let end = min(until, since.addingTimeInterval(w.off))
            if now >= end {
                phase = .scanning(until: now.addingTimeInterval(w.on))
                return .start(allowDuplicates: profile.allowsDuplicates)
            }
            return .none
        }
    }

    /// Bluetooth kapandi / izin gitti: durum sifirlanir (tarama zaten durmus sayilir).
    public mutating func reset() { phase = .idle; lastProfile = .off }
}
