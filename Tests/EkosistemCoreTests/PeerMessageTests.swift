import Testing
import Foundation
@testable import EkosistemCore

private let Self_contact = ContactRecord(kid: "12", ad: "Ayşe", numaralar: [ContactNumber(no: "+905551112233", tur: "cep")],
                                         favori: true, gruplar: ["Aile"], foto: "AQID")

private func json(_ e: PeerEnvelope) throws -> String { String(decoding: try PeerCodec.encode(e), as: UTF8.self) }

@Test func peerMesajTuruTumTipler() throws {
    let all: [PeerMessage] = [
        .hello(PeerHello(ad: "Mac", surum: "1.0", cihazId: "m1", platform: "mac")),
        .ping, .pong,
        .phoneState(PhoneState(ad: "Pixel", model: "P8", pil: 80, sarj: true, sinyal: 3, ag: "wifi")),
        .callState(CallState(durum: .caliyor, yon: .gelen, numara: "+90555", kisiAdi: "Ali", sureSn: nil)),
        .callAnswer, .callReject, .callHangup,
        .callDial(CallDial(numara: "123")),
        .contactsSearch(ContactsSearch(sorgu: "al")),
        .contactsResult(ContactsResult(kisiler: [PeerContact(ad: "Ali", numaralar: ["1", "2"])])),
        .callLogRecent(CallLogRecent(adet: 10)),
        .callLogResult(CallLogResult(kayitlar: [CallLogEntry(numara: "1", yon: .cevapsiz, zaman: 1_700_000_000, sureSn: 0)])),
        .contactsSync(ContactsSync(ofset: 80, adet: 40)),
        .contactsPage(ContactsPage(ofset: 0, toplam: 2, son: false, kisiler: [Self_contact])),
        .contactsChanged,
        .callLogSync(CallLogSync(ofset: 0)),
        .callLogPage(CallLogPage(ofset: 0, toplam: 1, son: true, kayitlar: [CallLogEntry(numara: "+905551112233", kisiAdi: "Ayşe", yon: .gelen, zaman: 1_700_000_000, sureSn: 42)])),
        .callLogChanged,
        .earbudState(EarbudState(cihazId: "e", ad: "QCY", baglanti: .telefon)),
        .earbudRelease(EarbudRelease(cihazAdresi: "AA:BB")),
        .earbudReleaseResult(EarbudResult(sonuc: .desteklenmiyor)),
        .earbudConnect(EarbudConnect(cihazAdresi: "AA:BB")),
        .earbudConnectResult(EarbudResult(sonuc: .tamam, cihazAdresi: "AA:BB")),
        .permState(PermState()),
        .ctlOwner(CtlOwner(cihazAdresi: "AA:BB:CC:DD:EE:FF", sahip: true)),
        .ctlWrite(CtlWrite(cihazAdresi: "AA:BB:CC:DD:EE:FF", bayt: "ff03fe0117")),
        .ctlNotify(CtlNotify(cihazAdresi: "AA:BB:CC:DD:EE:FF", tur: "yanit", bayt: "ff0517030100")),
        .mediaState(MediaState(caliyor: true, oturum: true, uygulama: "Spotify", baslik: "Sarki", sanatci: "Ali")),
        .mediaCmd(MediaCmd(komut: "sonraki")),
        .volState(VolState(cihaz: "mac", seviye: 40, sessiz: false)),
        .volSet(VolSet(hedef: "telefon", seviye: 70)),
        .error(PeerError(kod: "izin_yok", mesaj: "kisiler")),
    ]
    for (i, m) in all.enumerated() {
        let env = PeerEnvelope(m, id: i)
        #expect(try PeerCodec.decode(PeerCodec.encode(env)) == env)
    }
    #expect(Set(all.map(\.type)).count == all.count)
}

@Test func peerJSONBelgeylePirebir() throws {
    #expect(try json(PeerEnvelope(.ping, id: 7)) == #"{"id":7,"t":"ping"}"#)
    #expect(try json(PeerEnvelope(.callDial(CallDial(numara: "555")), id: 2)) == #"{"id":2,"numara":"555","t":"call.dial"}"#)
    #expect(try json(PeerEnvelope(.callState(CallState(durum: .bosta)))) == #"{"durum":"bosta","t":"call.state"}"#)
    #expect(try json(PeerEnvelope(.permState(PermState()))) == #"{"aramaGecmisi":false,"cagriYonetimi":false,"kisiler":false,"t":"perm.state"}"#)
}

@Test func peerMediaJSONBelgeylePirebir() throws {
    #expect(try json(PeerEnvelope(.mediaState(MediaState(caliyor: false, oturum: false)))) == #"{"caliyor":false,"oturum":false,"t":"media.state"}"#)
    #expect(try json(PeerEnvelope(.mediaState(MediaState(caliyor: true, oturum: true, uygulama: "Spotify", baslik: "Sarki", sanatci: "Ali")))) == #"{"baslik":"Sarki","caliyor":true,"oturum":true,"sanatci":"Ali","t":"media.state","uygulama":"Spotify"}"#)
    #expect(try json(PeerEnvelope(.mediaCmd(MediaCmd(komut: "oynat_duraklat")))) == #"{"komut":"oynat_duraklat","t":"media.cmd"}"#)
    var snap = PhoneSnapshot()
    snap.apply(PeerEnvelope(.mediaState(MediaState(caliyor: true, oturum: true))))
    #expect(snap.media?.caliyor == true)
    snap.disconnected()
    #expect(snap.media == nil)
}

@Test func peerVolJSONBelgeylePirebir() throws {
    #expect(try json(PeerEnvelope(.volState(VolState(cihaz: "mac", seviye: 40, sessiz: false)))) == #"{"cihaz":"mac","sessiz":false,"seviye":40,"t":"vol.state"}"#)
    #expect(try json(PeerEnvelope(.volSet(VolSet(hedef: "telefon", seviye: 70)))) == #"{"hedef":"telefon","seviye":70,"t":"vol.set"}"#)
    #expect(try json(PeerEnvelope(.volSet(VolSet(hedef: "mac", sessiz: true)))) == #"{"hedef":"mac","sessiz":true,"t":"vol.set"}"#)
    var snap = PhoneSnapshot()
    snap.apply(PeerEnvelope(.volState(VolState(cihaz: "mac", seviye: 10, sessiz: false))))
    #expect(snap.phoneVolume == nil)
    snap.apply(PeerEnvelope(.volState(VolState(cihaz: "telefon", seviye: 55, sessiz: true))))
    #expect(snap.phoneVolume?.seviye == 55)
    snap.disconnected()
    #expect(snap.phoneVolume == nil)
}

@Test func peerCtlJSONBelgeylePirebir() throws {
    #expect(try json(PeerEnvelope(.ctlOwner(CtlOwner(cihazAdresi: "AA:BB:CC:DD:EE:FF", sahip: true)))) == #"{"cihazAdresi":"AA:BB:CC:DD:EE:FF","sahip":true,"t":"ctl.owner"}"#)
    #expect(try json(PeerEnvelope(.ctlWrite(CtlWrite(cihazAdresi: "AA:BB:CC:DD:EE:FF", bayt: "ff03fe0117")))) == #"{"bayt":"ff03fe0117","cihazAdresi":"AA:BB:CC:DD:EE:FF","t":"ctl.write"}"#)
    #expect(try json(PeerEnvelope(.ctlWrite(CtlWrite(cihazAdresi: "AA:BB:CC:DD:EE:FF", bayt: "ff03fe0117", kar: "000d")))) == #"{"bayt":"ff03fe0117","cihazAdresi":"AA:BB:CC:DD:EE:FF","kar":"000d","t":"ctl.write"}"#)
    #expect(try PeerCodec.decode(Data(#"{"bayt":"ff03fe0117","cihazAdresi":"AA:BB:CC:DD:EE:FF","t":"ctl.write"}"#.utf8)).message == .ctlWrite(CtlWrite(cihazAdresi: "AA:BB:CC:DD:EE:FF", bayt: "ff03fe0117")))
    #expect(try PeerCodec.decode(Data(#"{"bayt":"ff03fe0117","cihazAdresi":"AA:BB:CC:DD:EE:FF","kar":"000b","t":"ctl.write"}"#.utf8)).message == .ctlWrite(CtlWrite(cihazAdresi: "AA:BB:CC:DD:EE:FF", bayt: "ff03fe0117", kar: "000b")))
    #expect(try json(PeerEnvelope(.ctlNotify(CtlNotify(cihazAdresi: "AA:BB:CC:DD:EE:FF", tur: "reklam", bayt: "1c52")))) == #"{"bayt":"1c52","cihazAdresi":"AA:BB:CC:DD:EE:FF","t":"ctl.notify","tur":"reklam"}"#)
    #expect(CtlHex.encode([0xFF, 0x03, 0xFE, 0x01, 0x17]) == "ff03fe0117")
    #expect(CtlHex.decode("ff03fe0117") == [0xFF, 0x03, 0xFE, 0x01, 0x17])
    #expect(CtlHex.decode("abc") == nil)
    #expect(CtlHex.decode("zz") == nil)
}

@Test func peerBilinmeyenTipVeBozukJSON() {
    #expect(throws: PeerMessageError.bilinmeyenTip("xyz")) { try PeerCodec.decode(Data(#"{"t":"xyz"}"#.utf8)) }
    #expect(throws: PeerMessageError.gecersizJSON) { try PeerCodec.decode(Data("not json".utf8)) }
    #expect(throws: PeerMessageError.gecersizJSON) { try PeerCodec.decode(Data(#"{"t":"call.dial"}"#.utf8)) }
    #expect(throws: PeerMessageError.gecersizJSON) { try PeerCodec.decode(Data(#"{"id":1}"#.utf8)) }
}

@Test func peerIzinKapisiVarsayilanKapali() {
    let perms = PermState()
    let req = PeerEnvelope(.contactsSearch(ContactsSearch(sorgu: "a")), id: 5)
    #expect(perms.denial(for: req) == PeerEnvelope(.error(PeerError(kod: "izin_yok", mesaj: "kisiler")), id: 5))
    #expect(perms.denial(for: PeerEnvelope(.callHangup)) != nil)
    #expect(perms.denial(for: PeerEnvelope(.callLogRecent(CallLogRecent()))) != nil)
    #expect(perms.denial(for: PeerEnvelope(.ping)) == nil)
    #expect(perms.denial(for: PeerEnvelope(.earbudRelease(EarbudRelease(cihazAdresi: "x")))) == nil)
    #expect(PermState(kisiler: true).denial(for: req) == nil)
}

// Kotlin tarafi ayni dizgileri uretmeli (PeerMessageTest).
@Test func peerKisiSenkronuJSONOrnekleri() throws {
    #expect(try json(PeerEnvelope(.contactsSync(ContactsSync(ofset: 80, adet: 40)), id: 3)) == #"{"adet":40,"id":3,"ofset":80,"t":"contacts.sync"}"#)
    #expect(try json(PeerEnvelope(.contactsSync(ContactsSync(ofset: 0)))) == #"{"ofset":0,"t":"contacts.sync"}"#)
    #expect(try json(PeerEnvelope(.contactsPage(ContactsPage(ofset: 0, toplam: 2, son: false, kisiler: [Self_contact])), id: 3))
        == #"{"id":3,"kisiler":[{"ad":"Ayşe","favori":true,"foto":"AQID","gruplar":["Aile"],"kid":"12","numaralar":[{"no":"+905551112233","tur":"cep"}]}],"ofset":0,"son":false,"t":"contacts.page","toplam":2}"#)
    #expect(try json(PeerEnvelope(.callLogPage(CallLogPage(ofset: 0, toplam: 1, son: true,
        kayitlar: [CallLogEntry(numara: "+905551112233", kisiAdi: "Ayşe", yon: .gelen, zaman: 1_700_000_000, sureSn: 42)]))))
        == #"{"kayitlar":[{"kisiAdi":"Ayşe","numara":"+905551112233","sureSn":42,"yon":"gelen","zaman":1700000000}],"ofset":0,"son":true,"t":"calllog.page","toplam":1}"#)
    #expect(try json(PeerEnvelope(.contactsChanged)) == #"{"t":"contacts.changed"}"#)
    #expect(try json(PeerEnvelope(.callLogChanged)) == #"{"t":"calllog.changed"}"#)
    // foto/gruplar opsiyonel degil sadece foto: fotosuz kayit foto alani icermez
    let bare = ContactRecord(kid: "1", ad: "A", numaralar: [])
    #expect(try json(PeerEnvelope(.contactsPage(ContactsPage(ofset: 0, toplam: 1, son: true, kisiler: [bare]))))
        == #"{"kisiler":[{"ad":"A","favori":false,"gruplar":[],"kid":"1","numaralar":[]}],"ofset":0,"son":true,"t":"contacts.page","toplam":1}"#)
}

@Test func peerKisiSenkronuIzinKapisi() {
    let sync = PeerEnvelope(.contactsSync(ContactsSync(ofset: 0)), id: 1)
    #expect(PermState().denial(for: sync) == PeerEnvelope(.error(PeerError(kod: "izin_yok", mesaj: "kisiler")), id: 1))
    #expect(PermState(kisiler: true).denial(for: sync) == nil)
    let log = PeerEnvelope(.callLogSync(CallLogSync(ofset: 0)), id: 2)
    #expect(PermState(kisiler: true).denial(for: log) != nil)
    #expect(PermState(aramaGecmisi: true).denial(for: log) == nil)
}
