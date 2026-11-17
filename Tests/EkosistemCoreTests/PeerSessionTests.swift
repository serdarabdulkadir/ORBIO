import Testing
import Foundation
@testable import EkosistemCore

private func helloOf(_ name: String, _ platform: String) -> PeerHello {
    PeerHello(ad: name, surum: "1", cihazId: name, platform: platform)
}

/// Bellek ici cift uc: bir ucun ciktisini digerinin girdisine tasir.
private struct Pair {
    var mac: PeerSession
    var phone: PeerSession
    var macEvents: [PeerSessionEvent] = []
    var phoneEvents: [PeerSessionEvent] = []

    init(macIdentity: PeerIdentity = PeerIdentity(), phoneIdentity: PeerIdentity = PeerIdentity(),
         macPins: Data? = nil, phonePins: Data? = nil) {
        mac = PeerSession(role: .mac, identity: macIdentity, hello: helloOf("Mac", "mac"), pinnedPeerKey: macPins)
        phone = PeerSession(role: .telefon, identity: phoneIdentity, hello: helloOf("Pixel", "android"), pinnedPeerKey: phonePins)
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

    mutating func connect() { pump(macOut: mac.start(), phoneOut: phone.start()) }
}

private func sas(_ events: [PeerSessionEvent]) -> String? {
    for e in events { if case .sasGerekli(let c, _) = e { return c } }
    return nil
}

@Test func ilkEslesmeAyniSASVeSifreliMesajTuru() throws {
    var pair = Pair()
    pair.connect()
    let macCode = try #require(sas(pair.macEvents)), phoneCode = try #require(sas(pair.phoneEvents))
    #expect(macCode == phoneCode && macCode.count == 6)
    #expect(pair.mac.state == .sasBekliyor && pair.phone.state == .sasBekliyor)

    pair.pump(macOut: pair.mac.confirmSAS(accepted: true))
    pair.pump(phoneOut: pair.phone.confirmSAS(accepted: true))
    #expect(pair.mac.state == .kurulu && pair.phone.state == .kurulu)
    // Karsilikli hello alindi.
    #expect(pair.macEvents.contains(.mesaj(PeerEnvelope(.hello(helloOf("Pixel", "android"))))))
    #expect(pair.phoneEvents.contains(.mesaj(PeerEnvelope(.hello(helloOf("Mac", "mac"))))))
    #expect(pair.macEvents.contains { if case .kuruldu(_, let n) = $0 { n == "Pixel" } else { false } })

    let req = PeerEnvelope(.contactsSearch(ContactsSearch(sorgu: "ali")), id: 9)
    var out = PeerSessionOutput(); out.frames = [try pair.mac.send(req)]
    pair.phoneEvents = []
    pair.pump(macOut: out)
    #expect(pair.phoneEvents == [.mesaj(req)])
    var back = PeerSessionOutput()
    let res = PeerEnvelope(.contactsResult(ContactsResult(kisiler: [PeerContact(ad: "Ali", numaralar: ["1"])])), id: 9)
    back.frames = [try pair.phone.send(res)]
    pair.macEvents = []
    pair.pump(phoneOut: back)
    #expect(pair.macEvents == [.mesaj(res)])
}

@Test func sabitlenmisAnahtarlaSASsizKurulur() throws {
    let mi = PeerIdentity(), pi = PeerIdentity()
    var pair = Pair(macIdentity: mi, phoneIdentity: pi, macPins: pi.publicKey, phonePins: mi.publicKey)
    pair.connect()
    #expect(pair.mac.state == .kurulu && pair.phone.state == .kurulu)
    #expect(sas(pair.macEvents) == nil)
    #expect(pair.macEvents.contains(.mesaj(PeerEnvelope(.hello(helloOf("Pixel", "android"))))))
}

@Test func sabitlenmisAnahtarUyusmazsaKapanir() {
    let mi = PeerIdentity(), pi = PeerIdentity()
    var pair = Pair(macIdentity: mi, phoneIdentity: pi, macPins: PeerIdentity().publicKey, phonePins: mi.publicKey)
    pair.connect()
    #expect(pair.mac.state == .kapali)
    #expect(pair.macEvents.contains(.kapandi(.anahtarUyusmuyor)))
}

@Test func sasReddiKapatir() {
    var pair = Pair()
    pair.connect()
    let o = pair.mac.confirmSAS(accepted: false)
    #expect(o.events == [.kapandi(.sasReddedildi)] && pair.mac.state == .kapali)
}

@Test func araadamFarkliSASGorur() throws {
    // Saldirgan iki tarafla ayri el sikisir: iki uctaki kod farkli olur.
    let attacker1 = PeerIdentity(), attacker2 = PeerIdentity()
    var mac = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("Mac", "mac"))
    var phone = PeerSession(role: .telefon, identity: PeerIdentity(), hello: helloOf("Pixel", "android"))
    var fakePhone = PeerSession(role: .telefon, identity: attacker1, hello: helloOf("Pixel", "android"))
    var fakeMac = PeerSession(role: .mac, identity: attacker2, hello: helloOf("Mac", "mac"))
    let m0 = mac.start(), p0 = phone.start(), fp0 = fakePhone.start(), fm0 = fakeMac.start()
    let macSide = mac.receive(fp0.frames[0]); let phoneSide = phone.receive(fm0.frames[0])
    _ = fakePhone.receive(m0.frames[0]); _ = fakeMac.receive(p0.frames[0])
    #expect(sas(macSide.events) != nil && sas(phoneSide.events) != nil)
    #expect(sas(macSide.events) != sas(phoneSide.events))
}

@Test func parcaliBaytlarlaElSikismaVeSifreliOkuma() throws {
    var mac = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("Mac", "mac"))
    var phone = PeerSession(role: .telefon, identity: PeerIdentity(), hello: helloOf("Pixel", "android"))
    let m0 = mac.start(), p0 = phone.start()
    var events: [PeerSessionEvent] = []
    for byte in p0.frames[0] { events += mac.receive(Data([byte])).events }
    #expect(sas(events) != nil)
    _ = phone.receive(m0.frames[0])
    let c = mac.confirmSAS(accepted: true)
    _ = phone.confirmSAS(accepted: true)
    var got: [PeerSessionEvent] = []
    for byte in c.frames[0] { got += phone.receive(Data([byte])).events }
    #expect(got == [.mesaj(PeerEnvelope(.hello(helloOf("Mac", "mac"))))])
}

@Test func tekrarVeBozukSifreliCerceveOturumuKapatir() throws {
    var pair = Pair()
    pair.connect()
    pair.pump(macOut: pair.mac.confirmSAS(accepted: true))
    pair.pump(phoneOut: pair.phone.confirmSAS(accepted: true))
    let frame = try pair.mac.send(PeerEnvelope(.ping, id: 1))
    #expect(pair.phone.receive(frame).events == [.mesaj(PeerEnvelope(.ping, id: 1))])
    let replay = pair.phone.receive(frame)
    #expect(replay.events == [.kapandi(.sifre(.tekrar))] && pair.phone.state == .kapali)

    var pair2 = Pair()
    pair2.connect()
    pair2.pump(macOut: pair2.mac.confirmSAS(accepted: true))
    pair2.pump(phoneOut: pair2.phone.confirmSAS(accepted: true))
    var bad = try pair2.mac.send(PeerEnvelope(.ping))
    bad[bad.count - 1] ^= 1
    #expect(pair2.phone.receive(bad).events == [.kapandi(.sifre(.kimlikDogrulama))])
}

@Test func yanlisDurumVeKotuElSikisma() throws {
    var s = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("Mac", "mac"))
    #expect(throws: PeerSessionError.yanlisDurum) { try s.send(PeerEnvelope(.ping)) }
    _ = s.start()
    let junk = try PeerFrame.encode(Data("{\"x\":1}".utf8))
    #expect(s.receive(junk).events == [.kapandi(.gecersizElSikisma)])
    // Cok buyuk cerceve baslik
    var s2 = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("Mac", "mac"))
    _ = s2.start()
    #expect(s2.receive(Data([0xFF, 0xFF, 0xFF, 0xFF])).events == [.kapandi(.cerceve(.cokBuyuk(0xFFFF_FFFF)))])
}

@Test func ayniRolReddedilir() {
    var a = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("A", "mac"))
    var b = PeerSession(role: .mac, identity: PeerIdentity(), hello: helloOf("B", "mac"))
    _ = a.start(); let ob = b.start()
    #expect(a.receive(ob.frames[0]).events == [.kapandi(.ayniRol)])
}

@Test func bilinmeyenTipOlumculDegil() throws {
    let mi = PeerIdentity(), pi = PeerIdentity()
    let mn = PeerCrypto.randomNonce(), pn = PeerCrypto.randomNonce()
    var mac = PeerSession(role: .mac, identity: mi, hello: helloOf("Mac", "mac"), pinnedPeerKey: pi.publicKey, nonce: mn)
    var phone = PeerSession(role: .telefon, identity: pi, hello: helloOf("Pixel", "android"), pinnedPeerKey: mi.publicKey, nonce: pn)
    let m0 = mac.start(), p0 = phone.start()
    _ = mac.receive(p0.frames[0]); _ = phone.receive(m0.frames[0])
    let keys = try PeerCrypto.deriveKeys(role: .telefon, identity: pi, peerPublicKey: mi.publicKey, macNonce: mn, phoneNonce: pn)
    let packet = try PeerCrypto.seal(Data(#"{"t":"yeni.tip"}"#.utf8), key: keys.phoneToMac, counter: 100)
    #expect(mac.receive(try PeerFrame.encode(packet)).events == [.bilinmeyenTip("yeni.tip")])
    #expect(mac.state == .kurulu)
    // Dogrulanmis ama bozuk JSON olumcul.
    let junk = try PeerCrypto.seal(Data("%%".utf8), key: keys.phoneToMac, counter: 101)
    #expect(mac.receive(try PeerFrame.encode(junk)).events == [.kapandi(.gecersizMesaj)])
}
