import Testing
import Foundation
@testable import EkosistemCore

private let adv = reading(l: 80, r: 90, c: 60)
private let sys = reading(overall: 70, source: .standart)

private func hit(_ g: Box<ProximityCardGate>, rssi: Int = -40, decoded: BatteryReading? = adv, system: BatteryReading? = nil,
                 locked: Bool = false, id: String = "d", _ time: TimeInterval) -> CardDecision {
    g.v.consider(deviceID: id, rssi: rssi, decoded: decoded, systemBattery: system, screenLocked: locked, at: at(time))
}

@Test func ikiUstUsteGucluPaketGerekir() {
    let g = Box(ProximityCardGate())
    #expect(hit(g, 0) == .bekle)
    #expect(hit(g, 1) == .goster(CardContent(deviceID: "d", battery: adv, source: .reklam)))
}

@Test func esikTamdaGecmez() {
    let g = Box(ProximityCardGate())
    #expect(hit(g, rssi: -55, 0) == .bekle)
    #expect(hit(g, rssi: -55, 1) == .bekle)   // > -55 gerekir
    #expect(hit(g, rssi: -54, 2) == .bekle)
    #expect(hit(g, rssi: -54, 3) != .bekle)
}

@Test func zayifPaketUstUsteSayaciSifirlar() {
    let g = Box(ProximityCardGate())
    _ = hit(g, 0)
    #expect(hit(g, rssi: -70, 1) == .bekle)
    #expect(hit(g, 2) == .bekle)
}

@Test func baskaCihazPaketiAraGirerseSayacSifirlanir() {
    let g = Box(ProximityCardGate())
    _ = hit(g, id: "a", 0)
    _ = hit(g, id: "b", 1)
    #expect(hit(g, id: "a", 2) == .bekle)
}

@Test func ayniCihaz60SnTekrarCikmaz() {
    let g = Box(ProximityCardGate())
    _ = hit(g, 0); _ = hit(g, 1)               // gosterildi t=1
    _ = hit(g, 2)
    #expect(hit(g, 3) == .bastir(.yakinZamandaGosterildi))
    _ = hit(g, 60)
    #expect(hit(g, 60.9) == .bastir(.yakinZamandaGosterildi))
    #expect({ if case .goster = hit(g, 61) { true } else { false } }())
}

@Test func baskaCihazIcinKartAyriSayilir() {
    let g = Box(ProximityCardGate())
    _ = hit(g, id: "a", 0); _ = hit(g, id: "a", 1)
    _ = hit(g, id: "b", 2)
    #expect(hit(g, id: "b", 3) != .bastir(.yakinZamandaGosterildi))
}

@Test func ekranKilitliyseCikmaz() {
    let g = Box(ProximityCardGate())
    _ = hit(g, locked: true, 0)
    #expect(hit(g, locked: true, 1) == .bastir(.ekranKilitli))
    #expect(g.v.visibleDeviceID == nil)
    // kilit acilinca kilitliyken sayilmis paketler yeterli: kart cikar
    #expect({ if case .goster = hit(g, locked: false, 2) { true } else { false } }())
}

@Test func reklamCozulemezseSistemPilineDuser() {
    let g = Box(ProximityCardGate())
    _ = hit(g, decoded: nil, system: sys, 0)
    #expect(hit(g, decoded: nil, system: sys, 1) == .goster(CardContent(deviceID: "d", battery: sys, source: .sistem)))
}

@Test func bosCozumVeSistemPiliYoksaKartYok() {
    let g = Box(ProximityCardGate())
    _ = hit(g, decoded: reading(source: .markaOzel), system: nil, 0)
    #expect(hit(g, decoded: reading(source: .markaOzel), system: nil, 1) == .bastir(.pilYok))
    #expect(g.v.visibleDeviceID == nil)
}

@Test func kart8SnSonraKapanir() {
    let g = Box(ProximityCardGate())
    _ = hit(g, 0); _ = hit(g, 1)
    #expect(g.v.visibleDeviceID == "d")
    #expect(!g.dismissIfExpired(at: at(8.9)))
    #expect(g.dismissIfExpired(at: at(9)))
    #expect(g.v.visibleDeviceID == nil)
    #expect(!g.dismissIfExpired(at: at(20)))
}

@Test func elleKapatma() {
    let g = Box(ProximityCardGate())
    #expect(!g.dismiss())
    _ = hit(g, 0); _ = hit(g, 1)
    #expect(g.dismiss())
    #expect(!g.dismiss())
}

private extension Box where T == ProximityCardGate {
    func dismissIfExpired(at now: Date) -> Bool { v.dismissIfExpired(at: now) }
    func dismiss() -> Bool { v.dismiss() }
}

@Test func zatenBagliysaCikmaz() {
    var g = ProximityCardGate()
    let b = reading(l: 80, r: 80)
    _ = g.consider(deviceID: "a", rssi: -40, decoded: b, systemBattery: nil, screenLocked: false, alreadyConnected: true, at: at(0))
    let d = g.consider(deviceID: "a", rssi: -40, decoded: b, systemBattery: nil, screenLocked: false, alreadyConnected: true, at: at(1))
    #expect(d == .bastir(.zatenBagli))
}

@Test func baglantiKopunca_zatenBagliBastirmasiTekrarEngeliSayilmaz() {
    var g = ProximityCardGate()
    let b = reading(l: 80, r: 80)
    for t in 0...3 {
        _ = g.consider(deviceID: "q", rssi: -30, decoded: b, systemBattery: nil, screenLocked: false, alreadyConnected: true, at: at(Double(t)))
    }
    let d = g.consider(deviceID: "q", rssi: -35, decoded: b, systemBattery: nil, screenLocked: false, at: at(4))
    #expect(d == .goster(CardContent(deviceID: "q", battery: b, source: .reklam)))
}
