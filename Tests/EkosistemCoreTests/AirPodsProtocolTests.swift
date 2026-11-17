import Testing
import Foundation
@testable import EkosistemCore

// Vektorler: LibrePods "AAP Definitions" belgesindeki ornek paketler ve bu belgelerden turetilmis sentetik paketler.
// Gercek cihaz kaydi degildir; kendi AirPods'la alinan kayitlar eklenecek (docs/airpods.md).

/// `04 00 04 00 <opcode LE> <govde>`
private func msg(_ opcode: UInt16, _ payload: [UInt8]) -> [UInt8] {
    [0x04, 0x00, 0x04, 0x00, UInt8(opcode & 0xFF), UInt8(opcode >> 8)] + payload
}

private func ctl(_ id: UInt8, _ value: UInt8) -> [UInt8] { msg(0x0009, [id, value, 0x00, 0x00, 0x00]) }

private func handshakeResponse(status: UInt16 = 0) -> [UInt8] {
    [0x01, 0x00, 0x04, 0x00, UInt8(status & 0xFF), UInt8(status >> 8), 0x01, 0x00, 0x02, 0x00,
     0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
}

// MARK: Paket kurucu

@Test func sabitPaketlerBelgeyleAyni() {
    #expect(AAPPacket.handshake == [0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0, 0, 0, 0, 0, 0, 0, 0])
    #expect(AAPPacket.requestNotifications == [0x04, 0x00, 0x04, 0x00, 0x0F, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])
    #expect(AAPPacket.featureEnable.count == 14)
    #expect(Array(AAPPacket.featureEnable.prefix(6)) == [0x04, 0x00, 0x04, 0x00, 0x4D, 0x00])
}

@Test func kontrolKomutlariBaytVektorleri() {
    #expect(AAPPacket.setListeningMode(.gurultuEngeli) == [0x04, 0x00, 0x04, 0x00, 0x09, 0x00, 0x0D, 0x02, 0, 0, 0])
    #expect(AAPPacket.setListeningMode(.kapali)[7] == 0x01)
    #expect(AAPPacket.setListeningMode(.seffaf)[7] == 0x03)
    #expect(AAPPacket.setListeningMode(.uyarlanir)[7] == 0x04)
    #expect(AAPPacket.setConversationalAwareness(true) == [0x04, 0x00, 0x04, 0x00, 0x09, 0x00, 0x28, 0x01, 0, 0, 0])
    #expect(AAPPacket.setConversationalAwareness(false)[7] == 0x02)
    #expect(AAPPacket.setEarDetection(true)[6...7] == [0x0A, 0x01])
    #expect(AAPPacket.setEarDetection(false)[6...7] == [0x0A, 0x02])
    #expect(AAPPacket.setOneBudANC(true)[6...7] == [0x1B, 0x01])
    #expect(AAPPacket.setAdaptiveStrength(wire: 50)[6...7] == [0x2E, 50])
    #expect(AAPPacket.setAdaptiveStrength(wire: 200)[7] == 100)
}

@Test func dinlemeModuBaytEslemesiCiftYonlu() {
    for mode in ListeningMode.allCases {
        #expect(ListeningMode(aapValue: mode.aapValue) == mode)
    }
    #expect(ListeningMode(aapValue: 0x00) == nil)
    #expect(ListeningMode(aapValue: 0x05) == nil)
}

// MARK: Ayristirici: pil

@Test func pilBelgeOrnegi() {
    let p: [UInt8] = [0x04, 0x00, 0x04, 0x00, 0x04, 0x00, 0x03,
                      0x02, 0x01, 0x64, 0x02, 0x01,
                      0x04, 0x01, 0x63, 0x01, 0x01,
                      0x08, 0x01, 0x11, 0x02, 0x01]
    guard case .battery(let entries)? = AAPParser.parse(p) else { Issue.record("pil bekleniyordu"); return }
    #expect(entries == [
        AAPBatteryEntry(component: .right, percent: 100, state: .discharging),
        AAPBatteryEntry(component: .left, percent: 99, state: .charging),
        AAPBatteryEntry(component: .caseBox, percent: 17, state: .discharging),
    ])
}

@Test func pilSahteVeBilinmeyenKayitlarAtilir() {
    // 127 (sahte), 255 (bagli degil), bilinmeyen bilesen 0x10, gecerli sol 50.
    let p = msg(0x0004, [0x04,
                         0x02, 0x01, 0x7F, 0x02, 0x01,
                         0x08, 0x01, 0xFF, 0x04, 0x01,
                         0x10, 0x01, 0x20, 0x02, 0x01,
                         0x04, 0x01, 0x32, 0x05, 0x01])
    #expect(AAPParser.parse(p) == .battery([AAPBatteryEntry(component: .left, percent: 50, state: .optimized)]))
}

@Test func pilKesikVeBosGovde() {
    #expect(AAPParser.parse(msg(0x0004, [])) == .battery([]))
    #expect(AAPParser.parse(msg(0x0004, [0x00])) == .battery([]))
    // 3 kayit bildirildi ama yalniz 1.5 kayit var: tam olan alinir, tasma yok.
    let p = msg(0x0004, [0x03, 0x04, 0x01, 0x40, 0x02, 0x01, 0x02, 0x01, 0x30])
    #expect(AAPParser.parse(p) == .battery([AAPBatteryEntry(component: .left, percent: 64, state: .discharging)]))
}

// MARK: Ayristirici: kontrol / mod

@Test func dinlemeModuBildirimi() {
    #expect(AAPParser.parse(ctl(0x0D, 0x01)) == .listeningMode(.kapali))
    #expect(AAPParser.parse(ctl(0x0D, 0x02)) == .listeningMode(.gurultuEngeli))
    #expect(AAPParser.parse(ctl(0x0D, 0x03)) == .listeningMode(.seffaf))
    #expect(AAPParser.parse(ctl(0x0D, 0x04)) == .listeningMode(.uyarlanir))
    #expect(AAPParser.parse(ctl(0x0D, 0x09)) == .unhandled(opcode: 0x0009))
    #expect(AAPParser.parse(ctl(0x0D, 0x00)) == .unhandled(opcode: 0x0009))
}

@Test func kontrolBooleanlari() {
    #expect(AAPParser.parse(ctl(0x28, 0x01)) == .conversationalAwarenessSetting(true))
    #expect(AAPParser.parse(ctl(0x28, 0x02)) == .conversationalAwarenessSetting(false))
    #expect(AAPParser.parse(ctl(0x28, 0x03)) == .unhandled(opcode: 0x0009))
    #expect(AAPParser.parse(ctl(0x0A, 0x01)) == .earDetectionSetting(true))
    #expect(AAPParser.parse(ctl(0x0A, 0x02)) == .earDetectionSetting(false))
    #expect(AAPParser.parse(ctl(0x1B, 0x02)) == .oneBudANC(false))
}

@Test func donguMaskesiVeUyarlanirSeviye() {
    #expect(AAPParser.parse(ctl(0x1A, 0x0E)) == .listeningModeCycle(mask: 0x0E))
    #expect(AAPParser.parse(ctl(0x1A, 0xFE)) == .listeningModeCycle(mask: 0x0E))
    #expect(AAPParser.parse(ctl(0x2E, 0)) == .adaptiveStrength(wire: 0))
    #expect(AAPParser.parse(ctl(0x2E, 100)) == .adaptiveStrength(wire: 100))
    #expect(AAPParser.parse(ctl(0x2E, 101)) == .unhandled(opcode: 0x0009))
}

@Test func bilinmeyenKontrolVeKisaGovde() {
    #expect(AAPParser.parse(ctl(0x7E, 0x01)) == .unhandled(opcode: 0x0009))
    #expect(AAPParser.parse(msg(0x0009, [0x0D])) == .unhandled(opcode: 0x0009))
    #expect(AAPParser.parse(msg(0x0009, [])) == .unhandled(opcode: 0x0009))
}

// MARK: Ayristirici: kulak algilama, rol, konusma

@Test func kulakAlgilamaYerlesimleri() {
    #expect(AAPParser.parse(msg(0x0006, [0x00, 0x01])) == .earDetection(primary: .inEar, secondary: .outOfEar))
    #expect(AAPParser.parse(msg(0x0006, [0x02, 0x02])) == .earDetection(primary: .inCase, secondary: .inCase))
    #expect(AAPParser.parse(msg(0x0006, [0x00, 0x07])) == .earDetection(primary: .inEar, secondary: .unknown(0x07)))
    #expect(AAPParser.parse(msg(0x0006, [0x00])) == .unhandled(opcode: 0x0006))
}

@Test func kulaklikRolu() {
    #expect(AAPParser.parse(msg(0x0008, [0x01, 0x00, 0x00, 0x00])) == .budRole(primaryIsLeft: true))
    #expect(AAPParser.parse(msg(0x0008, [0x02, 0x00, 0x01, 0x01])) == .budRole(primaryIsLeft: false))
    #expect(AAPParser.parse(msg(0x0008, [0x03, 0x00, 0x00, 0x00])) == .unhandled(opcode: 0x0008))
    #expect(AAPParser.parse(msg(0x0008, [0x01, 0x05, 0x00, 0x00])) == .unhandled(opcode: 0x0008))
    #expect(AAPParser.parse(msg(0x0008, [0x01, 0x00])) == .unhandled(opcode: 0x0008))
}

@Test func konusmaEtkinligiIkiSekil() {
    // Belge: 04 00 04 00 4B 00 02 00 01 [seviye]
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x01])) == .conversationActivity(.speaking))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x02])) == .conversationActivity(.speaking))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x03])) == .conversationActivity(.stopped))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x08])) == .conversationActivity(.normalVolume))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x09])) == .conversationActivity(.normalVolume))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x05])) == .conversationActivity(.speaking))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x01, 0x06])) == .conversationActivity(.other(0x06)))
    // Eski tek bayt sekli.
    #expect(AAPParser.parse(msg(0x004B, [0x01])) == .conversationActivity(.speaking))
    // Bozuk sekiller konusma sanilmaz.
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00, 0x02, 0x01])) == .unhandled(opcode: 0x004B))
    #expect(AAPParser.parse(msg(0x004B, [0x02, 0x00])) == .unhandled(opcode: 0x004B))
    #expect(AAPParser.parse(msg(0x004B, [])) == .unhandled(opcode: 0x004B))
}

// MARK: Ayristirici: cihaz bilgisi

private func infoPacket(_ strings: [String], prefix: [UInt8] = [0x02, 0xD5, 0x00, 0x04, 0x00]) -> [UInt8] {
    var payload = prefix
    for s in strings { payload += Array(s.utf8) + [0x00] }
    return msg(0x001D, payload)
}

@Test func cihazBilgisiCozulur() throws {
    let p = infoPacket(["AirPods Pro", "A3048", "Apple Inc.", "QXNRHHYXP6", "61.1868040002000000.2713", "61.1868040002000000.2713", "1.0.0"])
    guard case .deviceInfo(let info)? = AAPParser.parse(p) else { Issue.record("cihaz bilgisi bekleniyordu"); return }
    #expect(info.name == "AirPods Pro")
    #expect(info.modelNumber == "A3048")
    #expect(info.manufacturer == "Apple Inc.")
    #expect(info.serialNumber == "QXNRHHYXP6")
    #expect(info.firmwareVersion == "61.1868040002000000.2713")
    #expect(AppleModelCatalog.model(forModelNumber: info.modelNumber)?.id == 0x2420)
}

@Test func cihazBilgisiKisaVeBozuk() {
    // Yalniz ad + model: kalan alanlar bos.
    guard case .deviceInfo(let short)? = AAPParser.parse(infoPacket(["Benim AirPods", "A2096"])) else {
        Issue.record("kisa cihaz bilgisi cozulmedi"); return
    }
    #expect(short.name == "Benim AirPods" && short.modelNumber == "A2096" && short.serialNumber.isEmpty)
    // Yazdirilabilir bayt yok.
    #expect(AAPParser.parse(msg(0x001D, [0x02, 0xD5, 0x00, 0x04, 0x00, 0x00])) == .unhandled(opcode: 0x001D))
    #expect(AAPParser.parse(msg(0x001D, [])) == .unhandled(opcode: 0x001D))
    // Tek metin NUL ile bitmis: ad var, model bos.
    guard case .deviceInfo(let oneField)? = AAPParser.parse(infoPacket(["Sadece ad"])) else {
        Issue.record("tek alanli cihaz bilgisi cozulmedi"); return
    }
    #expect(oneField.name == "Sadece ad" && oneField.modelNumber.isEmpty)
    // NUL'suz tek metin: alan siniri yok, reddedilir.
    #expect(AAPParser.parse(msg(0x001D, [0x02, 0xD5, 0x00, 0x04, 0x00] + Array("Sadece ad".utf8))) == .unhandled(opcode: 0x001D))
}

// MARK: Ayristirici: tur, el sikisma, bozuk veri

@Test func elSikismaYanitiVeRet() {
    #expect(AAPParser.parse(handshakeResponse()) == .handshakeAccepted(major: 1, minor: 2, features: 7))
    #expect(AAPParser.parse(handshakeResponse(status: 0x0003)) == .handshakeRejected(status: 3))
    #expect(AAPParser.parse(Array(handshakeResponse().prefix(17))) == nil)
    #expect(AAPParser.parse([0x02, 0x00, 0x04, 0x00, 0x05, 0x00]) == .disconnected(status: 5))
    #expect(AAPParser.parse([0x02, 0x00, 0x04, 0x00]) == nil)
}

@Test func bozukKisaVeAAPOlmayanVeri() {
    #expect(AAPParser.parse([]) == nil)
    #expect(AAPParser.parse([0x04, 0x00, 0x04]) == nil)
    #expect(AAPParser.parse([0x04, 0x00, 0x04, 0x00]) == nil)            // opcode yok
    #expect(AAPParser.parse([0x04, 0x00, 0x04, 0x00, 0x04]) == nil)      // opcode yarim
    #expect(AAPParser.parse([0x04, 0x00, 0x09, 0x00, 0x04, 0x00]) == nil) // yanlis hizmet
    #expect(AAPParser.parse([0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00]) == nil) // bizim el sikismamiz
    #expect(AAPParser.parse([0x09, 0x00, 0x04, 0x00, 0x04, 0x00]) == nil) // bilinmeyen tur
    #expect(AAPParser.parse([UInt8](repeating: 0xFF, count: 64)) == nil)
}

@Test func bilinmeyenOpcodeOlayUretmez() {
    #expect(AAPParser.parse(msg(0x1234, [0x01, 0x02])) == .unhandled(opcode: 0x1234))
    #expect(AAPParser.parse(msg(0x0019, [0x01])) == .unhandled(opcode: 0x0019))
}

// MARK: Durum

@Test func durumPilBirlestirirVeKutuKorunur() throws {
    var s = AirPodsDeviceState()
    #expect(s.batteryReading(at: t0) == nil)
    s.apply(.battery([AAPBatteryEntry(component: .left, percent: 80, state: .charging),
                      AAPBatteryEntry(component: .right, percent: 90, state: .discharging),
                      AAPBatteryEntry(component: .caseBox, percent: 40, state: .discharging)]))
    // Sonraki bildirim yalniz sag: sol ve kutu korunur.
    s.apply(.battery([AAPBatteryEntry(component: .right, percent: 85, state: .discharging)]))
    let r = try #require(s.batteryReading(at: t0))
    #expect(r.left == 80 && r.right == 85 && r.caseLevel == 40)
    #expect(r.leftCharging && !r.rightCharging && !r.caseCharging)
    #expect(r.source == .markaOzel && r.timestamp == t0)
}

@Test func durumBaglantisizBilesenYuzdesiGosterilmez() throws {
    var s = AirPodsDeviceState()
    s.apply(.battery([AAPBatteryEntry(component: .left, percent: 70, state: .discharging),
                      AAPBatteryEntry(component: .caseBox, percent: 30, state: .disconnected)]))
    let r = try #require(s.batteryReading(at: t0))
    #expect(r.left == 70)
    #expect(r.caseLevel == nil)
}

@Test func durumTekParcaCihazGenelPil() throws {
    var s = AirPodsDeviceState()
    s.apply(.battery([AAPBatteryEntry(component: .single, percent: 55, state: .charging)]))
    let r = try #require(s.batteryReading(at: t0))
    #expect(r.overall == 55 && r.left == nil && r.right == nil)
    #expect(r.isCharging(.genel))
}

@Test func durumKulakAlgilamaSolSagEslemesi() {
    var s = AirPodsDeviceState()
    s.apply(.earDetection(primary: .inEar, secondary: .outOfEar))
    #expect(s.podsInEar == 1)
    #expect(s.leftPlacement == nil && s.rightPlacement == nil) // rol bilinmeden yon uydurulmaz
    s.apply(.budRole(primaryIsLeft: false))
    #expect(s.leftPlacement == .outOfEar && s.rightPlacement == .inEar)
    s.apply(.budRole(primaryIsLeft: true))
    #expect(s.leftPlacement == .inEar && s.rightPlacement == .outOfEar)
    s.apply(.earDetection(primary: .inEar, secondary: .inEar))
    #expect(s.podsInEar == 2)
    s.apply(.earDetection(primary: .inCase, secondary: .inCase))
    #expect(s.podsInEar == 0)
}

@Test func durumAyarlarVeKonusma() {
    var s = AirPodsDeviceState()
    s.apply(.listeningMode(.uyarlanir))
    s.apply(.listeningModeCycle(mask: 0x0E))
    s.apply(.earDetectionSetting(true))
    s.apply(.conversationalAwarenessSetting(true))
    s.apply(.oneBudANC(false))
    s.apply(.adaptiveStrength(wire: 40))
    #expect(s.listeningMode == .uyarlanir && s.listeningModeCycleMask == 0x0E)
    #expect(s.earDetectionEnabled == true && s.conversationalAwareness == true)
    #expect(s.oneBudANC == false && s.adaptiveStrengthWire == 40)
    #expect(!s.isSpeaking)
    s.apply(.conversationActivity(.speaking)); #expect(s.isSpeaking)
    s.apply(.conversationActivity(.other(9))); #expect(s.isSpeaking)   // bilinmeyen durum degistirmez
    s.apply(.conversationActivity(.stopped)); #expect(!s.isSpeaking)
    s.apply(.conversationActivity(.speaking))
    s.apply(.conversationActivity(.normalVolume)); #expect(!s.isSpeaking)
    // Protokol olaylari durumu bozmaz.
    s.apply(.unhandled(opcode: 0x1234)); s.apply(.disconnected(status: 1))
    #expect(s.listeningMode == .uyarlanir)
}

@Test func durumCodableGidisDonus() throws {
    var s = AirPodsDeviceState()
    s.apply(.listeningMode(.seffaf))
    s.apply(.earDetection(primary: .inEar, secondary: .unknown(9)))
    s.apply(.battery([AAPBatteryEntry(component: .left, percent: 12, state: .optimized)]))
    s.apply(.deviceInfo(AAPDeviceInfo(name: "A", modelNumber: "A3048", manufacturer: "M", serialNumber: "S", firmwareVersion: "F")))
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(AirPodsDeviceState.self, from: data) == s)
}

// MARK: Oturum

private let pro2 = AppleModelCatalog.model(forID: 0x2420)
private let gen2 = AppleModelCatalog.model(forID: 0x0F20)

@Test func oturumAcilistaYalnizIkiPaket() {
    var s = AAPSession(model: pro2)
    #expect(s.phase == .idle)
    #expect(s.begin() == [AAPPacket.handshake, AAPPacket.requestNotifications])
    #expect(s.phase == .handshaking)
    #expect(s.begin().isEmpty) // ikinci cagri tekrar yazmaz
}

@Test func oturumBeginOncesiVeKapaliykenPaketYoksayilir() {
    var s = AAPSession(model: pro2)
    #expect(s.receive(ctl(0x0D, 0x02)) == AAPSession.Step())
    _ = s.begin()
    s.close()
    #expect(s.phase == .closed)
    #expect(s.receive(ctl(0x0D, 0x02)) == AAPSession.Step())
    #expect(s.state.listeningMode == nil)
}

@Test func oturumIlkMesajHazirYaparVeOzellikBirKezGider() {
    var s = AAPSession(model: pro2)
    _ = s.begin()
    let first = s.receive(handshakeResponse())
    #expect(first.events == [.handshakeAccepted(major: 1, minor: 2, features: 7)])
    #expect(first.send == [AAPPacket.featureEnable])
    #expect(s.phase == .ready)
    let second = s.receive(ctl(0x0D, 0x04))
    #expect(second.send.isEmpty)
    #expect(s.state.listeningMode == .uyarlanir)
}

@Test func oturumYanitsizElSikismadaDaIlkMesajHazirYapar() {
    var s = AAPSession(model: pro2)
    _ = s.begin()
    let st = s.receive(msg(0x0004, [0x01, 0x04, 0x01, 0x50, 0x02, 0x01]))
    #expect(s.phase == .ready)
    #expect(st.send == [AAPPacket.featureEnable])
    #expect(s.state.left?.percent == 80)
}

@Test func oturumOzellikPaketiYalnizUyarlanirKonusmaModelleriIcin() {
    var a = AAPSession(model: gen2)
    _ = a.begin()
    #expect(a.receive(handshakeResponse()).send.isEmpty)
    var b = AAPSession(model: nil) // bilinmeyen model: iddia yok
    _ = b.begin()
    #expect(b.receive(handshakeResponse()).send.isEmpty)
    var c = AAPSession(model: AppleModelCatalog.model(forID: 0x0E20)) // Pro 1: uyarlanir / konusma yok
    _ = c.begin()
    #expect(c.receive(handshakeResponse()).send.isEmpty)
}

@Test func oturumRetVeKopmaKapatir() {
    var s = AAPSession(model: pro2)
    _ = s.begin()
    let r = s.receive(handshakeResponse(status: 1))
    #expect(r.events == [.handshakeRejected(status: 1)])
    #expect(s.phase == .closed)

    var t = AAPSession(model: pro2)
    _ = t.begin()
    _ = t.receive(handshakeResponse())
    _ = t.receive([0x02, 0x00, 0x04, 0x00, 0x00, 0x00])
    #expect(t.phase == .closed)
}

@Test func oturumBozukPaketDurumuDegistirmez() {
    var s = AAPSession(model: pro2)
    _ = s.begin()
    let st = s.receive([0x04, 0x00])
    #expect(st == AAPSession.Step())
    #expect(s.phase == .handshaking)
}

@Test func oturumKomutlarKapilari() {
    var s = AAPSession(model: pro2)
    #expect(s.listeningModeCommand(.seffaf) == nil)          // hazir degil
    _ = s.begin()
    #expect(s.listeningModeCommand(.seffaf) == nil)          // el sikisma suruyor
    _ = s.receive(handshakeResponse())
    #expect(s.listeningModeCommand(.seffaf) == AAPPacket.setListeningMode(.seffaf))
    _ = s.receive(ctl(0x0D, 0x03))
    #expect(s.listeningModeCommand(.seffaf) == nil)          // zaten bu mod: yazma yok
    #expect(s.listeningModeCommand(.uyarlanir) != nil)
    #expect(s.conversationalAwarenessCommand(true) != nil)
    _ = s.receive(ctl(0x28, 0x01))
    #expect(s.conversationalAwarenessCommand(true) == nil)
    #expect(s.conversationalAwarenessCommand(false) == AAPPacket.setConversationalAwareness(false))
    #expect(s.earDetectionCommand(false) == AAPPacket.setEarDetection(false))
    #expect(s.oneBudANCCommand(true) == AAPPacket.setOneBudANC(true))
    #expect(s.adaptiveStrengthCommand(wire: 30) == AAPPacket.setAdaptiveStrength(wire: 30))
    _ = s.receive(ctl(0x2E, 30))
    #expect(s.adaptiveStrengthCommand(wire: 30) == nil)
}

@Test func oturumModelDesteklemeyenKomutuGondermez() {
    var s = AAPSession(model: gen2) // AirPods 2: ses modu yok
    _ = s.begin()
    _ = s.receive(handshakeResponse())
    #expect(s.listeningModeCommand(.gurultuEngeli) == nil)
    #expect(s.conversationalAwarenessCommand(true) == nil)
    #expect(s.oneBudANCCommand(true) == nil)
    #expect(s.earDetectionCommand(false) != nil)

    var p1 = AAPSession(model: AppleModelCatalog.model(forID: 0x0E20)) // Pro 1: uyarlanir yok
    _ = p1.begin()
    _ = p1.receive(handshakeResponse())
    #expect(p1.listeningModeCommand(.uyarlanir) == nil)
    #expect(p1.listeningModeCommand(.gurultuEngeli) != nil)
}

@Test func oturumBilinmeyenModelTemkinli() {
    var s = AAPSession(model: nil)
    _ = s.begin()
    _ = s.receive(handshakeResponse())
    #expect(s.listeningModeCommand(.gurultuEngeli) != nil)
    #expect(s.listeningModeCommand(.uyarlanir) == nil)
    #expect(s.conversationalAwarenessCommand(true) == nil)
    #expect(s.earDetectionCommand(true) == nil)
    #expect(s.adaptiveStrengthCommand(wire: 10) == nil)
}

@Test func oturumKapaninceKomutYok() {
    var s = AAPSession(model: pro2)
    _ = s.begin()
    _ = s.receive(handshakeResponse())
    s.close()
    #expect(s.listeningModeCommand(.seffaf) == nil)
}
