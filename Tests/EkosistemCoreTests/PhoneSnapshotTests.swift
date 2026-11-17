import Testing
import Foundation
@testable import EkosistemCore

@Test func pingPongYanitiAyniIdyiTasir() {
    var s = PhoneSnapshot()
    let replies = s.apply(PeerEnvelope(.ping, id: 7))
    #expect(replies == [PeerEnvelope(.pong, id: 7)])
}

@Test func durumMesajlariOzeteIslenir() {
    var s = PhoneSnapshot()
    #expect(s.perm == nil)
    s.apply(PeerEnvelope(.phoneState(PhoneState(ad: "Pixel", model: "8", pil: 64, sarj: false, sinyal: 3, ag: "wifi"))))
    s.apply(PeerEnvelope(.callState(CallState(durum: .caliyor, yon: .gelen, numara: "555", kisiAdi: "Ayse"))))
    s.apply(PeerEnvelope(.permState(PermState(cagriYonetimi: true))))
    s.apply(PeerEnvelope(.earbudState(EarbudState(cihazId: "e1", ad: "QCY", baglanti: .telefon))))
    #expect(s.phone?.pil == 64)
    #expect(s.isRinging && s.isInCall)
    #expect(s.allows(.cagriYonetimi))
    #expect(!s.allows(.kisiler))
    #expect(s.earbuds["e1"]?.baglanti == .telefon)
}

@Test func izinBilinmiyorkenHicbirSeyIzinliDegil() {
    let s = PhoneSnapshot()
    for p in [PeerPermission.cagriYonetimi, .kisiler, .aramaGecmisi] { #expect(!s.allows(p)) }
}

@Test func kisiVeAramaGecmisiSonucuSaklanir() {
    var s = PhoneSnapshot()
    #expect(s.callLog == nil)
    s.apply(PeerEnvelope(.contactsResult(ContactsResult(kisiler: [PeerContact(ad: "Ali", numaralar: ["1"])]))))
    s.apply(PeerEnvelope(.callLogResult(CallLogResult(kayitlar: [CallLogEntry(numara: "1", yon: .cevapsiz, zaman: 5, sureSn: 0)]))))
    #expect(s.contacts.count == 1)
    #expect(s.callLog?.first?.yon == .cevapsiz)
}

@Test func hataMesajiSaklanirYanitUretmez() {
    var s = PhoneSnapshot()
    let r = s.apply(PeerEnvelope(.error(PeerError(kod: "izin_yok", mesaj: "kisiler")), id: 3))
    #expect(r.isEmpty)
    #expect(s.lastError?.kod == "izin_yok")
}

@Test func baglantiKopunceCanliDurumSilinirIzinlerKalir() {
    var s = PhoneSnapshot()
    s.apply(PeerEnvelope(.callState(CallState(durum: .acik, yon: .gelen))))
    s.apply(PeerEnvelope(.permState(PermState(kisiler: true))))
    s.apply(PeerEnvelope(.earbudState(EarbudState(cihazId: "e", ad: "x", baglanti: .bos))))
    s.disconnected()
    #expect(s.call.durum == .bosta)
    #expect(s.earbuds.isEmpty)
    #expect(s.perm?.kisiler == true)
    s.reset()
    #expect(s == PhoneSnapshot())
}

@Test func aramaGecisleri() {
    let idle = CallState(durum: .bosta)
    let ring = CallState(durum: .caliyor, yon: .gelen)
    let open = CallState(durum: .acik, yon: .gelen)
    #expect(PhoneSnapshot.transition(from: idle, to: ring) == .gelenBasladi)
    #expect(PhoneSnapshot.transition(from: ring, to: open) == .yok)
    #expect(PhoneSnapshot.transition(from: open, to: idle) == .bitti)
    #expect(PhoneSnapshot.transition(from: idle, to: CallState(durum: .araniyor, yon: .giden)) == .yok)
    #expect(PhoneSnapshot.transition(from: idle, to: idle) == .yok)
}

@Test func bilinmeyenTipYaniti() {
    let r = PhoneSnapshot.unknownTypeReply("x.y")
    #expect(r.message == .error(PeerError(kod: "bilinmeyen_tip", mesaj: "x.y")))
}


// MARK: Kapat (call.hangup) sifreli kanaldan gider; call.state yenilemeleri (sureSn) islenir

private struct HangupPair {
    var mac: PeerSession
    var phone: PeerSession
    var macEvents: [PeerSessionEvent] = []
    var phoneEvents: [PeerSessionEvent] = []

    init() {
        mac = PeerSession(role: .mac, identity: PeerIdentity(),
                          hello: PeerHello(ad: "Mac", surum: "1", cihazId: "m", platform: "mac"), pinnedPeerKey: nil)
        phone = PeerSession(role: .telefon, identity: PeerIdentity(),
                            hello: PeerHello(ad: "Pixel", surum: "1", cihazId: "p", platform: "android"), pinnedPeerKey: nil)
    }

    mutating func pump(macOut: PeerSessionOutput = .init(), phoneOut: PeerSessionOutput = .init()) {
        var m = macOut, p = phoneOut
        macEvents += m.events; phoneEvents += p.events
        while !m.frames.isEmpty || !p.frames.isEmpty {
            let toPhone = m.frames, toMac = p.frames
            m = .init(); p = .init()
            for f in toPhone { let o = phone.receive(f); p.frames += o.frames; phoneEvents += o.events }
            for f in toMac { let o = mac.receive(f); m.frames += o.frames; macEvents += o.events }
        }
    }

    mutating func establish() {
        pump(macOut: mac.start(), phoneOut: phone.start())
        pump(macOut: mac.confirmSAS(accepted: true))
        pump(phoneOut: phone.confirmSAS(accepted: true))
    }
}

@Test func callHangupSifreliKanaldanTelefonaUlasir() throws {
    var pair = HangupPair()
    pair.establish()
    #expect(pair.mac.state == .kurulu && pair.phone.state == .kurulu)
    var out = PeerSessionOutput(); out.frames = [try pair.mac.send(PeerEnvelope(.callHangup))]
    pair.phoneEvents = []
    pair.pump(macOut: out)
    #expect(pair.phoneEvents == [.mesaj(PeerEnvelope(.callHangup))])
    #expect(PeerEnvelope(.callHangup).message.type == "call.hangup")
}

@Test func callStateYenilemeleriSureSnIleIslenir() throws {
    var pair = HangupPair()
    pair.establish()
    var snapshot = PhoneSnapshot()
    for sure in [1, 2, 3] {
        let state = CallState(durum: .acik, yon: .giden, numara: "555", kisiAdi: "Ali", sureSn: sure)
        var out = PeerSessionOutput(); out.frames = [try pair.phone.send(PeerEnvelope(.callState(state)))]
        pair.macEvents = []
        pair.pump(phoneOut: out)
        guard case .mesaj(let envelope)? = pair.macEvents.first else { Issue.record("mesaj gelmedi"); return }
        snapshot.apply(envelope)
        #expect(snapshot.call.sureSn == sure)
        #expect(snapshot.isInCall)
    }
    var out = PeerSessionOutput(); out.frames = [try pair.phone.send(PeerEnvelope(.callState(CallState(durum: .bosta))))]
    pair.macEvents = []
    pair.pump(phoneOut: out)
    guard case .mesaj(let end)? = pair.macEvents.first else { Issue.record("mesaj gelmedi"); return }
    let before = snapshot.call
    snapshot.apply(end)
    #expect(!snapshot.isInCall)
    #expect(PhoneSnapshot.transition(from: before, to: snapshot.call) == .bitti)
}

private func rec(_ i: Int) -> ContactRecord {
    ContactRecord(kid: "\(i)", ad: "K\(i)", numaralar: [ContactNumber(no: "555000\(i)", tur: "cep")])
}

@Test func kisiSenkronuIlkIstekIzinleBaslar() {
    var s = PhoneSnapshot()
    #expect(s.apply(PeerEnvelope(.permState(PermState()))).isEmpty)
    let r = s.apply(PeerEnvelope(.permState(PermState(kisiler: true, aramaGecmisi: true))))
    #expect(r.map(\.message.type) == ["contacts.sync", "calllog.sync"])
    // ikinci perm.state ayni anda tekrar istek uretmez
    #expect(s.apply(PeerEnvelope(.permState(PermState(kisiler: true, aramaGecmisi: true)))).isEmpty)
}

@Test func kisiSayfalariBirlesirSonaKadarSonrakiniIster() {
    var s = PhoneSnapshot()
    s.apply(PeerEnvelope(.permState(PermState(kisiler: true))))
    var r = s.apply(PeerEnvelope(.contactsPage(ContactsPage(ofset: 0, toplam: 3, son: false, kisiler: [rec(1), rec(2)]))))
    #expect(r == [PeerEnvelope(.contactsSync(ContactsSync(ofset: 2, adet: PhoneSnapshot.contactPageSize)))])
    // sira disi sayfa yoksayilir
    #expect(s.apply(PeerEnvelope(.contactsPage(ContactsPage(ofset: 9, toplam: 3, son: true, kisiler: [rec(9)])))).isEmpty)
    #expect(s.contactBook.count == 2)
    r = s.apply(PeerEnvelope(.contactsPage(ContactsPage(ofset: 2, toplam: 3, son: true, kisiler: [rec(3)]))))
    #expect(r.isEmpty)
    #expect(s.contactBook.map(\.kid) == ["1", "2", "3"])
    #expect(s.contactsLoaded && !s.contactsLoading)
}

@Test func kisiDegisinceBastanIsterIzinKapaninceVeKopuncaBellekSilinir() {
    var s = PhoneSnapshot()
    s.apply(PeerEnvelope(.permState(PermState(kisiler: true, aramaGecmisi: true))))
    s.apply(PeerEnvelope(.contactsPage(ContactsPage(ofset: 0, toplam: 1, son: true, kisiler: [rec(1)]))))
    s.apply(PeerEnvelope(.callLogPage(CallLogPage(ofset: 0, toplam: 1, son: true, kayitlar: [CallLogEntry(numara: "1", yon: .giden, zaman: 1, sureSn: 2)]))))
    #expect(s.callLog?.count == 1 && s.callLogLoaded)
    let ch = s.apply(PeerEnvelope(.contactsChanged))
    #expect(ch == [PeerEnvelope(.contactsSync(ContactsSync(ofset: 0, adet: PhoneSnapshot.contactPageSize)))])
    s.apply(PeerEnvelope(.permState(PermState(kisiler: false, aramaGecmisi: true))))
    #expect(s.contactBook.isEmpty && !s.contactsLoaded)
    s.apply(PeerEnvelope(.permState(PermState(kisiler: true, aramaGecmisi: true))))
    s.apply(PeerEnvelope(.contactsPage(ContactsPage(ofset: 0, toplam: 1, son: true, kisiler: [rec(1)]))))
    s.disconnected()
    #expect(s.contactBook.isEmpty && s.callLog == nil && !s.contactsLoaded && !s.callLogLoaded)
}

@Test func izinsizKisiSayfasiYoksayilir() {
    var s = PhoneSnapshot()
    s.apply(PeerEnvelope(.permState(PermState())))
    s.apply(PeerEnvelope(.contactsPage(ContactsPage(ofset: 0, toplam: 1, son: true, kisiler: [rec(1)]))))
    #expect(s.contactBook.isEmpty)
}
