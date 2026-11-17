// docs/islevler.md 2.3: otomatik gecis kurali. Saf deger tipi; zaman disaridan verilir.
import Foundation

public enum AutoSwitchReason: String, Sendable, Codable {
    case cagriGeldi, medyaBasladi
}

public struct AutoSwitchDecision: Equatable, Sendable {
    public let deviceID: String
    public let target: PlaybackHost
    public let reason: AutoSwitchReason
}

/// "Geri al" teklifi: gecisten sonra 30 sn gecerli.
public struct UndoOffer: Equatable, Sendable {
    public let deviceID: String
    public let restoreTo: PlaybackHost
    public let expiresAt: Date
}

/// Cagri bitince 5 sn sonra eski sahibe donus onerisi (otomatik donmez).
public struct ReturnSuggestion: Equatable, Sendable {
    public let deviceID: String
    public let owner: PlaybackHost
}

public struct AutoSwitchPolicy: Sendable {
    public static let minimumSwitchInterval: TimeInterval = 10
    public static let undoWindow: TimeInterval = 30
    public static let returnSuggestionDelay: TimeInterval = 5

    private struct Switch { var at: Date; var from: PlaybackHost }
    private struct PendingReturn { var due: Date; var owner: PlaybackHost }

    private var lastSwitch: [String: Switch] = [:]
    private var pendingReturns: [String: PendingReturn] = [:]
    private var callOrigin: [String: PlaybackHost] = [:]
    private var offer: UndoOffer?

    public init() {}

    private static func host(of state: DeviceState) -> PlaybackHost? {
        switch state {
        case .bagliBuMac: .buMac
        case .bagliTelefon: .telefon
        default: nil
        }
    }

    /// Telefon `cagri_basladi` yayinladi. Kulaklik Mac'teyse telefona gecis kararlari.
    public mutating func callStarted(deviceID: String, rule: AutoSwitchRule, state: DeviceState, at now: Date) -> AutoSwitchDecision? {
        guard rule == .telefondaCagriGelince, Self.host(of: state) == .buMac else { return nil }
        callOrigin[deviceID] = .buMac
        pendingReturns[deviceID] = nil
        return AutoSwitchDecision(deviceID: deviceID, target: .telefon, reason: .cagriGeldi)
    }

    /// Cagri bitti: 5 sn sonra, cagri oncesi sahibe donus onerisi hazirlanir.
    public mutating func callEnded(deviceID: String, at now: Date) {
        guard let origin = callOrigin.removeValue(forKey: deviceID) else { return }
        pendingReturns[deviceID] = PendingReturn(due: now.addingTimeInterval(Self.returnSuggestionDelay), owner: origin)
    }

    /// Suresi gelen donus onerilerini (bir kez) verir.
    public mutating func dueReturnSuggestions(at now: Date) -> [ReturnSuggestion] {
        let due = pendingReturns.filter { $0.value.due <= now }
        for key in due.keys { pendingReturns[key] = nil }
        return due.map { ReturnSuggestion(deviceID: $0.key, owner: $0.value.owner) }.sorted { $0.deviceID < $1.deviceID }
    }

    /// `host` tarafinda medya basladi. Kulaklik baska taraftaysa ve son gecisten 10 sn gectiyse gecis.
    public mutating func mediaStarted(deviceID: String, on host: PlaybackHost, rule: AutoSwitchRule, state: DeviceState, at now: Date) -> AutoSwitchDecision? {
        guard rule == .medyaBaslayanCihaza, let owner = Self.host(of: state), owner != host else { return nil }
        if let last = lastSwitch[deviceID], now.timeIntervalSince(last.at) < Self.minimumSwitchInterval { return nil }
        return AutoSwitchDecision(deviceID: deviceID, target: host, reason: .medyaBasladi)
    }

    /// Otomatik gecis basariyla bittiginde cagrilir; "Geri al" penceresini acar.
    @discardableResult
    public mutating func recordSwitch(_ decision: AutoSwitchDecision, from: PlaybackHost, at now: Date) -> UndoOffer {
        lastSwitch[decision.deviceID] = Switch(at: now, from: from)
        let o = UndoOffer(deviceID: decision.deviceID, restoreTo: from, expiresAt: now.addingTimeInterval(Self.undoWindow))
        offer = o
        return o
    }

    /// Elle yapilan gecis de tekrar gecis araligini baslatir (teklif acmaz).
    public mutating func recordManualSwitch(deviceID: String, at now: Date) {
        lastSwitch[deviceID] = Switch(at: now, from: .buMac)
        if offer?.deviceID == deviceID { offer = nil }
    }

    /// Gecerli "Geri al" teklifi (30 sn dolduysa nil).
    public func undoOffer(at now: Date) -> UndoOffer? {
        guard let offer, now < offer.expiresAt else { return nil }
        return offer
    }

    /// "Geri al" kullanildi: teklif kapanir ve geri gecis tekrar-gecis araligini sayar.
    public mutating func consumeUndo(at now: Date) -> UndoOffer? {
        guard let o = undoOffer(at: now) else { offer = nil; return nil }
        offer = nil
        lastSwitch[o.deviceID] = Switch(at: now, from: o.restoreTo)
        return o
    }
}
