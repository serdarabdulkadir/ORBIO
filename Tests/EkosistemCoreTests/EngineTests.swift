import Testing
import Foundation
@testable import EkosistemCore

@MainActor
private struct Rig {
    let clock = ManualClock(start: t0)
    let script: Script
    let engine: EkosistemEngine

    init(_ queues: [String: [Behavior]] = [:], peerAvailable: Bool = true) {
        script = Script(queues)
        engine = EkosistemEngine(clock: clock, peer: FakePeer(script: script, available: peerAvailable),
                                 route: FakeRoute(script: script),
                                 systemBattery: { _ in reading(overall: 55, source: .standart, time: t0) })
    }

    func add(_ id: String = "d", multipoint: Bool = false, rule: AutoSwitchRule = .hicbirZaman) {
        var s = DeviceSettings(); s.autoSwitch = rule
        engine.handle(.kayit(Device(id: id, name: "QCY T13 ANC", profile: .tws, supportsMultipoint: multipoint), settings: s))
    }

    func state(_ id: String = "d") -> DeviceState? { engine.devices.first { $0.id == id }?.state }

    func advance(_ s: TimeInterval) { clock.advance(by: s); engine.tick() }

    var outputs: [EngineOutput] { engine.recentOutputs }
}

@MainActor @Test func kayitliCihazDurumAkisi() {
    let r = Rig(); r.add()
    #expect(r.state() == .bilinmiyor)
    r.engine.handle(.reklam(deviceID: "d", rssi: -80, battery: nil))
    #expect(r.state() == .yakinda)
    r.advance(11)
    #expect(r.state() == .bilinmiyor)
    r.advance(60)
    #expect(r.state() == .bagliDegil)
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    #expect(r.state() == .bagliBuMac)
    #expect(r.engine.lastUpdate == r.clock.now)
}

@MainActor @Test func bilinmeyenCihazOlaylariYoksayilirUnutKaldirir() {
    let r = Rig()
    r.engine.handle(.baglanti(deviceID: "x", .buMac))
    #expect(r.engine.devices.isEmpty)
    r.add()
    r.engine.handle(.unut(deviceID: "d"))
    #expect(r.engine.devices.isEmpty)
    #expect(r.engine.settings["d"] == nil)
}

@MainActor @Test func pilOlayiVeSoluklukMotordaGorunur() {
    let r = Rig(); r.add()
    r.engine.handle(.pil(deviceID: "d", reading(l: 82, r: 80, c: 18, time: t0)))
    let b = r.engine.devices[0].battery
    #expect(b?.left == 82 && b?.caseLevel == 18)
    r.advance(31 * 60)
    #expect(r.engine.devices[0].battery?.isStale(at: r.clock.now) == true)
}

@MainActor @Test func yaklasmaKartiGosterilirBastirilirKapanir() {
    let r = Rig(); r.add()
    let b = reading(l: 80, r: 80, c: 40)
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(!r.outputs.contains { if case .kartGoster = $0 { true } else { false } })
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(r.outputs.contains(.kartGoster(CardContent(deviceID: "d", battery: b, source: .reklam))))
    r.advance(7.9)
    #expect(!r.outputs.contains(.kartKapat))
    r.advance(0.1)
    #expect(r.outputs.contains(.kartKapat))
    // 60 sn icinde tekrar yok
    let before = r.outputs.count
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(r.outputs.count == before)
}

@MainActor @Test func kartCozulemezseSistemPilineDusurVeEkranKilidiBastirir() {
    let r = Rig(); r.add()
    r.engine.handle(.ekranKilit(true))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: nil))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: nil))
    #expect(r.outputs.isEmpty)
    r.engine.handle(.ekranKilit(false))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: nil))
    guard case .kartGoster(let c)? = r.outputs.last else { Issue.record("kart yok"); return }
    #expect(c.source == .sistem && c.battery.overall == 55)
    r.engine.handle(.ekranKilit(true))   // acik kart kilitle kapanir
    #expect(r.outputs.last == .kartKapat)
}

@MainActor @Test func sessizVeYakinlikKapaliKartVeDusukPiliSusturur() {
    let r = Rig(); r.add()
    r.engine.updateSettings(for: "d") { $0.silent = true }
    let b = reading(l: 10, r: 10)
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(r.outputs.isEmpty)
    r.engine.updateSettings(for: "d") { $0.silent = false; $0.proximityCard = false }
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(r.outputs.allSatisfy { if case .kartGoster = $0 { false } else { true } })
}

@MainActor @Test func dusukPilHisterezisMotordaCalisir() {
    let r = Rig(); r.add()
    r.engine.handle(.pil(deviceID: "d", reading(l: 20, r: 80, time: r.clock.now)))
    r.engine.handle(.pil(deviceID: "d", reading(l: 15, r: 80, time: r.clock.now)))
    let alerts = r.outputs.filter { if case .bildirim(.dusukPil) = $0 { true } else { false } }
    #expect(alerts.count == 1)
}

@MainActor @Test func elleGecisDurumuGuncellerIpucuVeHataBildirir() async {
    let r = Rig(); r.add()
    r.engine.handle(.baglanti(deviceID: "d", .telefon))
    #expect(await r.engine.transfer(deviceID: "d", to: .buMac) == .basarili)
    #expect(r.state() == .bagliBuMac)
    #expect(r.engine.transferringDeviceID == nil && r.engine.transferPhase == .bosta)

    let r2 = Rig(peerAvailable: false); r2.add()
    #expect(await r2.engine.transfer(deviceID: "d", to: .buMac) == .ipucu)
    #expect(r2.outputs.contains(.bildirim(.gecisIpucu(deviceID: "d"))))

    let r3 = Rig(["route.connect": [.fail]]); r3.add()
    #expect(await r3.engine.transfer(deviceID: "d", to: .buMac) == .baglanamadi)
    #expect(r3.outputs.contains(.bildirim(.gecisHatasi(deviceID: "d"))))
    #expect(await r3.engine.transfer(deviceID: "yok", to: .buMac) == .iptal)
}

@MainActor @Test func medyaKuraliOtomatikGecerGeriAlirVePencereDolar() async {
    let r = Rig(); r.add(rule: .medyaBaslayanCihaza)
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    r.engine.handle(.medya(host: .telefon))
    await r.engine.waitForAutomaticTransfer()
    #expect(r.state() == .bagliTelefon)
    #expect(r.outputs.contains { if case .bildirim(.otomatikGecis(_, let u)) = $0 { u.restoreTo == .buMac } else { false } })
    #expect(r.engine.undoOffer != nil)

    r.advance(5)
    #expect(await r.engine.undoLastSwitch() == .basarili)
    #expect(r.state() == .bagliBuMac)
    #expect(r.engine.undoOffer == nil)
    #expect(await r.engine.undoLastSwitch() == nil)
}

@MainActor @Test func geriAlPenceresi30SnSonraKapanir() async {
    let r = Rig(); r.add(rule: .medyaBaslayanCihaza)
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    r.engine.handle(.medya(host: .telefon))
    await r.engine.waitForAutomaticTransfer()
    r.advance(30)
    #expect(r.engine.undoOffer == nil)
    #expect(await r.engine.undoLastSwitch() == nil)
    #expect(r.state() == .bagliTelefon)
}

@MainActor @Test func medyaTekrarGecisiOnSnIcindeEngellenir() async {
    let r = Rig(); r.add(rule: .medyaBaslayanCihaza)
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    r.engine.handle(.medya(host: .telefon))
    await r.engine.waitForAutomaticTransfer()
    r.advance(5)
    r.engine.handle(.medya(host: .buMac))
    await r.engine.waitForAutomaticTransfer()
    #expect(r.state() == .bagliTelefon)    // 10 sn dolmadi
    r.advance(5)
    r.engine.handle(.medya(host: .buMac))
    await r.engine.waitForAutomaticTransfer()
    #expect(r.state() == .bagliBuMac)
}

@MainActor @Test func cagriKuraliTelefonaGecerBitinceDonusOnerir() async {
    let r = Rig(); r.add(rule: .telefondaCagriGelince)
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    r.engine.handle(.cagri(started: true))
    await r.engine.waitForAutomaticTransfer()
    #expect(r.state() == .bagliTelefon)
    r.engine.handle(.cagri(started: false))
    r.advance(4.9)
    #expect(!r.outputs.contains { if case .bildirim(.geriDonusOnerisi) = $0 { true } else { false } })
    r.advance(0.1)
    #expect(r.outputs.contains(.bildirim(.geriDonusOnerisi(ReturnSuggestion(deviceID: "d", owner: .buMac)))))
    #expect(r.state() == .bagliTelefon)   // otomatik donmez
}

@MainActor @Test func kuralHicbirZamanSaglanirsaGecisYok() async {
    let r = Rig(); r.add()
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    r.engine.handle(.cagri(started: true))
    r.engine.handle(.medya(host: .telefon))
    await r.engine.waitForAutomaticTransfer()
    #expect(r.state() == .bagliBuMac)
    #expect(await r.script.calls.isEmpty)
}

@MainActor @Test func olayAkisiVeTikSaatiIleCalisir() async {
    let r = Rig(); r.add()
    let (stream, cont) = AsyncStream.makeStream(of: DeviceEvent.self)
    let task = Task { await r.engine.run(events: stream) }
    cont.yield(.baglanti(deviceID: "d", .buMac))
    await waitForSleepers(r.clock)          // tik dongusu uyudu
    #expect(r.state() == .bagliBuMac)
    cont.finish()
    await task.value
}

@MainActor @Test func kulaklikZatenBuMacteBagliysaKartCikmaz() {
    let r = Rig(); r.add()
    r.engine.handle(.baglanti(deviceID: "d", .buMac))
    let b = reading(l: 80, r: 80, c: 40)
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(r.outputs.allSatisfy { if case .kartGoster = $0 { false } else { true } })
    // Baglanti kopunca (yakinda) ayni reklamlar karti gosterir.
    r.engine.handle(.baglanti(deviceID: "d", .degil))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    r.engine.handle(.reklam(deviceID: "d", rssi: -40, battery: b))
    #expect(r.outputs.contains(.kartGoster(CardContent(deviceID: "d", battery: b, source: .reklam))))
}
