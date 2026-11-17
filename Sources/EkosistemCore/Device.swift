// Cihaz modeli: profil, baglanti durumu, pil okumasi ve cihaz basina ayarlar.
import Foundation

public enum DeviceProfile: String, Sendable, Codable, CaseIterable {
    case standart, tws, apple
}

/// docs/islevler.md 2.1: bir cihaz yalniz bu durumlardan birinde olur.
public enum DeviceState: String, Sendable, Codable {
    case bagliBuMac, bagliTelefon, bagliDegil, yakinda, bilinmiyor
}

/// Ses sahibi taraf (Mac ya da telefon).
public enum PlaybackHost: String, Sendable, Codable {
    case buMac, telefon
}

public enum BatterySource: String, Sendable, Codable {
    case markaOzel, standart, yok

    /// Yuksek deger daha oncelikli (marka GATT / reklam cozumu > standart > yok).
    var rank: Int {
        switch self {
        case .markaOzel: 2
        case .standart: 1
        case .yok: 0
        }
    }
}

public enum BatteryChannel: String, Sendable, Codable, CaseIterable {
    case sol, sag, kutu, genel
}

/// Bir pil okumasi. `nil` yuzde = bilinmiyor (arayuzde "--").
public struct BatteryReading: Equatable, Sendable, Codable {
    /// Bu sureden eski okuma soluk gosterilir.
    public static let staleAfter: TimeInterval = 30 * 60

    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    /// Tek degerli standart Battery Service okumasi (sol / sag ayrimi yok).
    public var overall: Int?
    public var leftCharging: Bool
    public var rightCharging: Bool
    public var caseCharging: Bool
    public var source: BatterySource
    public var timestamp: Date

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, overall: Int? = nil,
                leftCharging: Bool = false, rightCharging: Bool = false, caseCharging: Bool = false,
                source: BatterySource, timestamp: Date) {
        self.left = left; self.right = right; self.caseLevel = caseLevel; self.overall = overall
        self.leftCharging = leftCharging; self.rightCharging = rightCharging; self.caseCharging = caseCharging
        self.source = source; self.timestamp = timestamp
    }

    /// 30 dk'dan eskiyse (ya da hic deger yoksa) soluk.
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(timestamp) > Self.staleAfter
    }

    public func level(_ channel: BatteryChannel) -> Int? {
        switch channel {
        case .sol: left
        case .sag: right
        case .kutu: caseLevel
        case .genel: overall
        }
    }

    public func isCharging(_ channel: BatteryChannel) -> Bool {
        switch channel {
        case .sol: leftCharging
        case .sag: rightCharging
        case .kutu: caseCharging
        case .genel: leftCharging || rightCharging || caseCharging
        }
    }

    public var hasAnyValue: Bool {
        BatteryChannel.allCases.contains { level($0) != nil }
    }

    /// Reklam cozucusunun ciktisindan okuma uretir (bilinmeyen nibble nil olur).
    public init(info: ProximityPairingInfo, at time: Date) {
        func pct(_ l: BatteryLevel) -> Int? { if case .percent(let p) = l { p } else { nil } }
        self.init(left: pct(info.left), right: pct(info.right), caseLevel: pct(info.caseBattery),
                  leftCharging: info.leftCharging, rightCharging: info.rightCharging,
                  caseCharging: info.caseCharging, source: .markaOzel, timestamp: time)
    }
}

/// Dinleme modu (ses modu). Uygulanmasi model surucusu gerektirir (Katman B).
public enum ListeningMode: String, Sendable, Codable, CaseIterable {
    case kapali, gurultuEngeli, seffaf, uyarlanir
}

/// 2.3: cihaz basina bir secenek; varsayilan `hicbirZaman`.
public enum AutoSwitchRule: String, Sendable, Codable, CaseIterable {
    case hicbirZaman, telefondaCagriGelince, medyaBaslayanCihaza
}

public struct DeviceSettings: Equatable, Sendable, Codable {
    public var autoSwitch: AutoSwitchRule = .hicbirZaman
    public var earDetection = true
    /// Yaklasma pil karti.
    public var proximityCard = true
    /// Sessiz: kart ve dusuk pil bildirimi gosterilmez.
    public var silent = false
    public var listeningMode: ListeningMode = .kapali

    public init() {}
}

public struct Device: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public var name: String
    public var profile: DeviceProfile
    public var supportsMultipoint: Bool
    public var state: DeviceState
    public var battery: BatteryReading?
    /// Apple / Beats model kimligi (Proximity Pairing reklami ya da AAP cihaz bilgisinden); bilinmiyorsa nil.
    public var appleModelID: UInt16?
    /// AAP kanalindan okunan AirPods durumu (ses modu, kulak algilama, konusma farkindaligi...); kanal yoksa nil.
    public var airPods: AirPodsDeviceState?

    public init(id: String, name: String, profile: DeviceProfile = .standart, supportsMultipoint: Bool = false,
                state: DeviceState = .bilinmiyor, battery: BatteryReading? = nil, appleModelID: UInt16? = nil) {
        self.id = id; self.name = name; self.profile = profile
        self.supportsMultipoint = supportsMultipoint; self.state = state; self.battery = battery
        self.appleModelID = appleModelID
    }

    /// Katalogdaki Apple / Beats modeli (yalniz `.apple` profilinde ve kimlik biliniyorsa).
    public var appleModel: AppleModel? {
        guard profile == .apple, let id = appleModelID else { return nil }
        return AppleModelCatalog.model(forID: id)
    }

    /// Apple modelinin yetenegi; model bilinmiyorsa false.
    public func supports(_ capability: AppleCapabilities) -> Bool { appleModel?.supports(capability) ?? false }

    /// Apple profilinde model biliniyorsa modelin modlari (ses modu olmayan modelde bos), bilinmiyorsa "Uyarlanir" dahil hepsi.
    public var availableListeningModes: [ListeningMode] {
        guard profile == .apple else { return [.kapali, .gurultuEngeli, .seffaf] }
        return appleModel?.listeningModes ?? ListeningMode.allCases
    }

    /// QCY yetenegi bu cihaz profilinde arastirmada dogrulanmis mi (yalniz `.tws` profili).
    public func isQcyVerified(_ capability: QcyCapability) -> Bool {
        profile == .tws && capability.isVerified
    }

    /// Etkin mi: dogrulanmis ya da APK'dan okunmus (cihazda denenmemis) yetenek; yalniz `.tws` profili.
    public func isQcyEnabled(_ capability: QcyCapability) -> Bool {
        profile == .tws && capability.isEnabled
    }

    public var verifiedQcyCapabilities: [QcyCapability] {
        QcyCapability.allCases.filter { isQcyVerified($0) }
    }
}
