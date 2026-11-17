import Testing
import Foundation
@testable import EkosistemCore

private func helloOf(_ name: String, _ platform: String) -> PeerHello {
    PeerHello(ad: name, surum: "1", cihazId: name, platform: platform)
}

/// Mac kapili, telefon verilen kodla; ciktilari karsilikli tasir.
private func run(gate: PairingGate, phoneCode: String?) -> (mac: PeerSession, macEvents: [PeerSessionEvent], phoneFrames: [Data]) {
    var mac = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("Mac", "mac"), pairingGate: gate)
    var phone = PeerSession(role: .telefon, identity: PeerIdentity(), hello: helloOf("Pixel", "android"), pairingCode: phoneCode)
    _ = mac.start()
    let hs = phone.start()
    var events: [PeerSessionEvent] = []
    var back: [Data] = []
    for f in hs.frames { let o = mac.receive(f); events += o.events; back += o.frames }
    return (mac, events, back)
}

@Test func dogruKodSASa_gecer_ve_tekKullanimlik() {
    let gate = PairingGate(clock: ManualClock())
    gate.open(code: "123456")
    let r = run(gate: gate, phoneCode: "123456")
    #expect(r.mac.state == .sasBekliyor)
    #expect(gate.state.code == nil)   // tuketildi
}

@Test func aktifKodYokkenKodsuzAkisEskisiGibiCalisir() {
    let gate = PairingGate(clock: ManualClock())
    let r = run(gate: gate, phoneCode: nil)
    #expect(r.mac.state == .sasBekliyor)
    #expect(r.phoneFrames.isEmpty)   // hs_red gonderilmez
}

@Test func aktifKodVarkenKodsuzTelefonKodGerekliAlirVeSayilmaz() {
    let gate = PairingGate(clock: ManualClock())
    gate.open(code: "123456")
    let r = run(gate: gate, phoneCode: nil)
    #expect(r.mac.state == .kapali)
    #expect(r.macEvents.contains(.kapandi(.kodGerekli)))
    #expect(r.phoneFrames.count == 1)   // yalniz hs_red (kod_gerekli)
    // Kodsuz deneme hak yemez: dogru kodla hala girilir.
    #expect(run(gate: gate, phoneCode: "123456").mac.state == .sasBekliyor)
}

@Test func yanlisKodUcDenemedeKilitlenir() {
    let gate = PairingGate(clock: ManualClock())
    gate.open(code: "123456")
    #expect(run(gate: gate, phoneCode: "000000").macEvents.contains(.kapandi(.kodYanlis)))
    #expect(run(gate: gate, phoneCode: "222222").macEvents.contains(.kapandi(.kodYanlis)))
    #expect(run(gate: gate, phoneCode: "111111").macEvents.contains(.kapandi(.kodKilitlendi)))
    // Kilitlendikten sonra dogru kod bile kabul edilmez.
    let late = run(gate: gate, phoneCode: "123456")
    #expect(late.mac.state == .kapali)
    #expect(gate.state.locked)
    gate.close()
    #expect(run(gate: gate, phoneCode: nil).mac.state == .sasBekliyor)   // iptal: eski davranis
}

@Test func besDakikaSonraKodGecersizOlurVeKapiPasifleser() {
    let clock = ManualClock()
    let gate = PairingGate(clock: clock)
    gate.open(code: "123456")
    clock.advance(by: PairingGate.lifetime + 1)
    #expect(run(gate: gate, phoneCode: nil).mac.state == .sasBekliyor)
    #expect(gate.state.code == nil)
}

@Test func uretilenKodAltiHaneli() {
    let gate = PairingGate(clock: ManualClock())
    for _ in 0..<50 {
        let c = gate.open().code
        #expect(c?.count == 6 && c?.allSatisfy(\.isNumber) == true)
    }
}

@Test func kapisizMacEskiDavranisiKorur() {
    var mac = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("Mac", "mac"))
    var phone = PeerSession(role: .telefon, identity: PeerIdentity(), hello: helloOf("Pixel", "android"))
    _ = mac.start()
    for f in phone.start().frames { _ = mac.receive(f) }
    #expect(mac.state == .sasBekliyor)
}
