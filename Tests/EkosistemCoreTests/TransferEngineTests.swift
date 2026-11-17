import Testing
import Foundation
@testable import EkosistemCore

private func make(_ script: Script, available: Bool = true, clock: ManualClock, phases: PhaseLog? = nil) -> TransferEngine {
    TransferEngine(peer: FakePeer(script: script, available: available), route: FakeRoute(script: script), clock: clock) {
        phases?.add($0)
    }
}

@Test func multipointMaceBaglanVeCikisiCevirir() async {
    let s = Script(), clock = ManualClock()
    let out = await make(s, clock: clock).transfer(deviceID: "d", to: .buMac, multipoint: true)
    #expect(out == .basarili)
    #expect(await s.calls == ["route.connect", "route.active"])
}

@Test func multipointTelefonaSahiplikIster() async {
    let s = Script(), clock = ManualClock()
    let out = await make(s, clock: clock).transfer(deviceID: "d", to: .telefon, multipoint: true)
    #expect(out == .basarili)
    #expect(await s.calls == ["peer.owner"])
}

@Test func maceGecisBirakSonraBaglan() async {
    let s = Script(), clock = ManualClock(), phases = PhaseLog()
    let out = await make(s, clock: clock, phases: phases).transfer(deviceID: "d", to: .buMac, multipoint: false)
    #expect(out == .basarili)
    #expect(await s.calls == ["peer.release", "route.connect"])
    #expect(phases.all == [.birakIsteniyor, .baglaniyor(attempt: 1), .bosta])
}

@Test func birakYanitsizsa3SnSonraYerelBaglanIpucuIle() async {
    let s = Script(["peer.release": [.hang]]), clock = ManualClock()
    let engine = make(s, clock: clock)
    let task = Task { await engine.transfer(deviceID: "d", to: .buMac, multipoint: false) }
    await waitForSleepers(clock)
    clock.advance(by: 2.9)
    await settle()
    #expect(await s.count("route.connect") == 0)  // 3 sn dolmadi
    clock.advance(by: 0.1)
    #expect(await task.value == .ipucu)
    #expect(await s.calls == ["peer.release", "route.connect"])
    #expect(await s.count("peer.undo") == 0)
}

@Test func kanalYoksaYerelBaglanVeIpucu() async {
    let s = Script(), clock = ManualClock()
    let out = await make(s, available: false, clock: clock).transfer(deviceID: "d", to: .buMac, multipoint: false)
    #expect(out == .ipucu)
    #expect(await s.calls == ["route.connect"])
}

@Test func baglanBasarisizsaBirTekrarSonraBasarili() async {
    let s = Script(["route.connect": [.fail, .ok]]), clock = ManualClock(), phases = PhaseLog()
    let out = await make(s, clock: clock, phases: phases).transfer(deviceID: "d", to: .buMac, multipoint: false)
    #expect(out == .basarili)
    #expect(await s.count("route.connect") == 2)
    #expect(await s.count("peer.undo") == 0)
    #expect(phases.all.contains(.baglaniyor(attempt: 2)))
}

@Test func baglan8SnZamanAsimiIkiDenemeSonraGeriAl() async {
    let s = Script(["route.connect": [.hang]]), clock = ManualClock()
    let engine = make(s, clock: clock)
    let task = Task { await engine.transfer(deviceID: "d", to: .buMac, multipoint: false) }
    await waitForSleepers(clock)
    clock.advance(by: 7.9)
    await settle()
    #expect(await s.count("route.connect") == 1)
    clock.advance(by: 0.1)      // birinci deneme bitti, ikincisi baslar
    await waitForSleepers(clock)
    #expect(await s.count("route.connect") == 2)
    clock.advance(by: 8)
    #expect(await task.value == .baglanamadi)
    #expect(await s.calls.last == "peer.undo")
}

@Test func baglanmadanOnceBirakGonderilmediyseGeriAlYok() async {
    let s = Script(["route.connect": [.fail]]), clock = ManualClock()
    let out = await make(s, available: false, clock: clock).transfer(deviceID: "d", to: .buMac, multipoint: false)
    #expect(out == .baglanamadi)
    #expect(await s.count("peer.undo") == 0)
}

@Test func iptalEdilirseGeriAlGonderilir() async {
    let s = Script(["route.connect": [.hang]]), clock = ManualClock()
    let engine = make(s, clock: clock)
    let task = Task { await engine.transfer(deviceID: "d", to: .buMac, multipoint: false) }
    await waitForSleepers(clock)
    task.cancel()
    #expect(await task.value == .iptal)
    #expect(await s.calls == ["peer.release", "route.connect", "peer.undo"])
}

@Test func telefonaGecisKoparVeTelefonBaglanir() async {
    let s = Script(), clock = ManualClock()
    let out = await make(s, clock: clock).transfer(deviceID: "d", to: .telefon, multipoint: false)
    #expect(out == .basarili)
    #expect(await s.calls == ["route.disconnect", "peer.connect"])
}

@Test func telefonBaglanamazsaMacYenidenBaglanir() async {
    let s = Script(["peer.connect": [.fail]]), clock = ManualClock()
    let out = await make(s, clock: clock).transfer(deviceID: "d", to: .telefon, multipoint: false)
    #expect(out == .baglanamadi)
    #expect(await s.calls == ["route.disconnect", "peer.connect", "peer.connect", "route.connect"])
}

@Test func telefonaGecisKanalYoksaYalnizKoparIpucu() async {
    let s = Script(), clock = ManualClock()
    let out = await make(s, available: false, clock: clock).transfer(deviceID: "d", to: .telefon, multipoint: false)
    #expect(out == .ipucu)
    #expect(await s.calls == ["route.disconnect"])
}
