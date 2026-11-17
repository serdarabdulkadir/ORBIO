// On kontrol: motoru sahte saatle sahte olay dizisiyle oynatir, gecisleri stdout'a yazar. 0 = tamam, 1 = hata.
import Foundation
import EkosistemCore

private struct STRoute: AudioRoute {
    var failConnect = false
    struct Failed: Error {}
    func connect(deviceID: String) async throws { if failConnect { throw Failed() } }
    func disconnect(deviceID: String) async throws {}
    func makeActiveOutput(deviceID: String) async throws {}
}

private struct STPeer: PeerChannel {
    var available = true
    var isAvailable: Bool { get async { available } }
    func requestRelease(deviceID: String) async throws {}
    func requestConnect(deviceID: String) async throws {}
    func requestPlaybackOwnership(deviceID: String) async throws {}
    func requestUndo(deviceID: String) async {}
}

@MainActor
private final class Report {
    var failures = 0
    func section(_ title: String) { print("\n== \(title)") }
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("[\(ok ? "OK" : "HATA")] \(name)\(detail.isEmpty ? "" : " -> \(detail)")")
        if !ok { failures += 1 }
    }
}

@MainActor
func runSelfTest() async -> Int32 {
    let r = Report()
    let clock = ManualClock()
    let id = "st-qcy", other = "st-redmi"
    func reading(_ l: Int?, _ rt: Int?, _ c: Int?, cc: Bool = false) -> BatteryReading {
        BatteryReading(left: l, right: rt, caseLevel: c, caseCharging: cc, source: .markaOzel, timestamp: clock.now)
    }
    func make(peer: Bool = true, failConnect: Bool = false) -> EkosistemEngine {
        let e = EkosistemEngine(clock: clock, peer: STPeer(available: peer), route: STRoute(failConnect: failConnect),
                                systemBattery: { _ in nil })
        var s = DeviceSettings(); s.autoSwitch = .medyaBaslayanCihaza
        e.handle(.kayit(Device(id: id, name: "QCY T13 ANC", profile: .tws), settings: s))
        e.handle(.kayit(Device(id: other, name: "Redmi Buds 6", profile: .tws, supportsMultipoint: true)))
        return e
    }
    func state(_ e: EkosistemEngine, _ i: String = "") -> DeviceState? { e.devices.first { $0.id == (i.isEmpty ? id : i) }?.state }
    func tick(_ e: EkosistemEngine, _ s: TimeInterval) { clock.advance(by: s); e.tick() }

    r.section("1. Durum akisi (docs 2.1)")
    var e = make()
    r.check("kayit sonrasi bilinmiyor", state(e) == .bilinmiyor)
    e.handle(.reklam(deviceID: id, rssi: -80, battery: nil))
    r.check("reklam -> yakinda", state(e) == .yakinda)
    tick(e, 11)
    r.check("10 sn reklam yok -> bilinmiyor", state(e) == .bilinmiyor)
    tick(e, 60)
    r.check("sinyal yok -> bagliDegil", state(e) == .bagliDegil)
    e.handle(.baglanti(deviceID: id, .buMac))
    r.check("IOBluetooth baglandi -> bagliBuMac", state(e) == .bagliBuMac)

    r.section("2. Dusuk pil (2.5) ve soluk pil")
    e.handle(.pil(deviceID: id, reading(82, 80, 25)))
    e.handle(.pil(deviceID: id, reading(82, 80, 18)))
    e.handle(.pil(deviceID: id, reading(82, 80, 15)))
    var lows = e.recentOutputs.filter { if case .bildirim(.dusukPil) = $0 { true } else { false } }
    r.check("kutu <= %20 icin tek bildirim", lows.count == 1, "\(lows)")
    e.handle(.pil(deviceID: id, reading(82, 80, 26)))
    e.handle(.pil(deviceID: id, reading(82, 80, 19)))
    lows = e.recentOutputs.filter { if case .bildirim(.dusukPil) = $0 { true } else { false } }
    r.check("%25 ustune cikinca yeniden kurulur", lows.count == 2)
    tick(e, 31 * 60)
    r.check("30 dk sonra pil soluk", e.devices.first?.battery?.isStale(at: clock.now) == true)

    r.section("3. Yaklasma karti (2.4)")
    e = make()
    let adv = reading(80, 82, 60)
    e.handle(.reklam(deviceID: id, rssi: -40, battery: adv))
    r.check("ilk paket: kart yok", !e.recentOutputs.contains { if case .kartGoster = $0 { true } else { false } })
    e.handle(.reklam(deviceID: id, rssi: -40, battery: adv))
    r.check("ikinci paket: kart", e.recentOutputs.contains(.kartGoster(CardContent(deviceID: id, battery: adv, source: .reklam))))
    tick(e, 8)
    r.check("8 sn sonra kapanir", e.recentOutputs.last == .kartKapat)
    let n = e.recentOutputs.count
    e.handle(.reklam(deviceID: id, rssi: -40, battery: adv)); e.handle(.reklam(deviceID: id, rssi: -40, battery: adv))
    r.check("60 sn icinde tekrar yok", e.recentOutputs.count == n)

    r.section("4. Ses gecisi (2.2)")
    e = make()
    e.handle(.baglanti(deviceID: id, .telefon))
    var out = await e.transfer(deviceID: id, to: .buMac)
    r.check("telefondan Mac'e gecis", out == .basarili && state(e) == .bagliBuMac, "\(out)")
    e = make(peer: false)
    out = await e.transfer(deviceID: id, to: .buMac)
    r.check("kanal yok: yerel baglan + ipucu", out == .ipucu && e.recentOutputs.contains(.bildirim(.gecisIpucu(deviceID: id))), "\(out)")
    e = make(failConnect: true)
    out = await e.transfer(deviceID: id, to: .buMac)
    r.check("baglanamadi: hata bildirimi", out == .baglanamadi && e.recentOutputs.contains(.bildirim(.gecisHatasi(deviceID: id))), "\(out)")

    r.section("5. Otomatik gecis (2.3) ve geri al")
    e = make()
    e.handle(.baglanti(deviceID: id, .buMac))
    e.handle(.medya(host: .telefon))
    await e.waitForAutomaticTransfer()
    r.check("telefonda medya basladi -> telefona gecti", state(e) == .bagliTelefon)
    r.check("Geri al teklifi var", e.undoOffer != nil)
    let undo = await e.undoLastSwitch()
    r.check("Geri al -> Mac'e dondu", undo == .basarili && state(e) == .bagliBuMac, "\(String(describing: undo))")
    e.handle(.medya(host: .telefon))
    await e.waitForAutomaticTransfer()
    r.check("10 sn dolmadan tekrar gecis yok", state(e) == .bagliBuMac)
    tick(e, 10)
    e.handle(.medya(host: .telefon))
    await e.waitForAutomaticTransfer()
    r.check("10 sn sonra tekrar gecer", state(e) == .bagliTelefon)
    tick(e, 30)
    r.check("30 sn sonra Geri al penceresi kapali", e.undoOffer == nil)

    print("\nOzet: \(r.failures == 0 ? "TAMAM" : "\(r.failures) HATA")")
    return r.failures == 0 ? 0 : 1
}
