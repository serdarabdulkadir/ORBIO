// Kanal sahibi + aktarim: QCY kulaklik tek BLE kontrol baglantisi kabul eder. Sahip taraf GATT'i tutar,
// diger taraf komutlari sifreli peer kanalindan (ctl.write) yollar, yanitlari (ctl.notify) geri alir.
// Cakisma: iki taraf da sahip bildirirse Mac sahip kalir, telefon birakir.
import Foundation
import EkosistemCore

@MainActor
final class ControlRelay {
    private let provider: BluetoothProvider
    private let sendMessage: (PeerMessage) -> Bool
    private var sessionUp = false
    /// Telefonun sahip oldugunu bildirdigi cihazlar.
    private var phoneOwns: Set<String> = []
    /// Arayuz icin: telefon uzerinden kontrol degisti.
    var onRemoteChange: ((String, Bool) -> Void)?

    init(provider: BluetoothProvider, send: @escaping (PeerMessage) -> Bool) {
        self.provider = provider
        sendMessage = send
        provider.relayWrite = { [weak self] id, bytes, kar in
            guard let self, self.sessionUp, self.phoneOwns.contains(id) else { return false }
            return self.sendMessage(.ctlWrite(CtlWrite(cihazAdresi: id, bayt: CtlHex.encode(bytes), kar: kar)))
        }
        provider.relayReady = { [weak self] id in
            guard let self else { return false }
            return self.sessionUp && self.phoneOwns.contains(id)
        }
        provider.onLocalOwner = { [weak self] id, owned in self?.localOwnerChanged(id, owned) }
        provider.onQcyNotify = { [weak self] id, kind, bytes in
            guard let self, self.sessionUp else { return }
            _ = self.sendMessage(.ctlNotify(CtlNotify(cihazAdresi: id, tur: kind, bayt: CtlHex.encode(bytes))))
        }
    }

    func sessionEstablished(ownedIDs: [String]) {
        sessionUp = true
        for id in ownedIDs { _ = sendMessage(.ctlOwner(CtlOwner(cihazAdresi: id, sahip: true))) }
    }

    func sessionClosed() {
        sessionUp = false
        for id in phoneOwns { release(id) }
        phoneOwns.removeAll()
    }

    func receive(_ message: PeerMessage) {
        switch message {
        case .ctlOwner(let o):
            let id = Self.normalize(o.cihazAdresi)
            if o.sahip {
                let current: ControlOwner = provider.ownsChannel(id) ? .mac : (phoneOwns.contains(id) ? .phone : .none)
                if ControlOwnership.resolve(current: current, claimant: .phone, userInitiated: false) == .mac {
                    // Ilk yoneten Mac: zorla alinmaz; telefona bildir, birakmasini bekle.
                    _ = sendMessage(.ctlOwner(CtlOwner(cihazAdresi: id, sahip: true)))
                } else if phoneOwns.insert(id).inserted {
                    provider.setRemoteOwner(id, true)
                    onRemoteChange?(id, true)
                }
            } else if phoneOwns.remove(id) != nil {
                release(id)
            }
        case .ctlWrite(let w):
            let id = Self.normalize(w.cihazAdresi)
            guard let bytes = CtlHex.decode(w.bayt) else { return }
            provider.writeRelayed(id, bytes, kar: w.kar)
        case .ctlNotify(let n):
            let id = Self.normalize(n.cihazAdresi)
            guard phoneOwns.contains(id), let bytes = CtlHex.decode(n.bayt) else { return }
            provider.ingestRemote(id, kind: n.tur, bytes: bytes)
        default:
            break
        }
    }

    /// Oturum acik mi (arayuz: devir dugmesi yalniz oturum varken gorunur).
    var isSessionUp: Bool { sessionUp }

    /// "Kontrolu Mac'e al": mevcut `ctl.owner` sahip=true ile Mac sahipligini ister; cakisma kuralina gore telefon
    /// birakir (kendi `ctl.owner` sahip=false yanitiyla), Mac dogrudan GATT'e baglanir. 20 sn icinde olmazsa vazgecilir.
    func takeControl(_ id: String) {
        guard sessionUp, phoneOwns.contains(id) else { return }
        _ = sendMessage(.ctlOwner(CtlOwner(cihazAdresi: id, sahip: true)))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.sessionUp, !self.provider.ownsChannel(id), self.phoneOwns.contains(id) else { return }
            // Telefon birakmadi: istegi geri cek, telefon sahip kalir.
            _ = self.sendMessage(.ctlOwner(CtlOwner(cihazAdresi: id, sahip: false)))
        }
    }

    /// "Kontrolu telefona ver": Mac GATT'i birakir, `ctl.owner` sahip=false yollar; telefon baglanip sahip=true bildirir.
    /// 30 sn icinde telefon sahip olmazsa Mac yeniden dogrudan baglanir.
    func giveControl(_ id: String) {
        guard sessionUp, provider.ownsChannel(id) else { return }
        provider.yieldChannel(id)
        _ = sendMessage(.ctlOwner(CtlOwner(cihazAdresi: id, sahip: false)))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !self.phoneOwns.contains(id) else { return }
            self.provider.clearYield(id)
        }
    }

    private func release(_ id: String) {
        provider.setRemoteOwner(id, false)
        onRemoteChange?(id, false)
    }

    private func localOwnerChanged(_ id: String, _ owned: Bool) {
        if owned, phoneOwns.remove(id) != nil { onRemoteChange?(id, false) }
        if sessionUp { _ = sendMessage(.ctlOwner(CtlOwner(cihazAdresi: id, sahip: owned))) }
    }

    private static func normalize(_ a: String) -> String { a.uppercased().replacingOccurrences(of: "-", with: ":") }
}
