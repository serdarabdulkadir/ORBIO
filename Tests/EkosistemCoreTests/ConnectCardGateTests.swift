import Testing
import Foundation
@testable import EkosistemCore

private func gate() -> Box<ConnectCardGate> { Box(ConnectCardGate(startedAt: t0)) }

private func obs(_ g: Box<ConnectCardGate>, _ s: DeviceState, id: String = "d", prox: Bool = true, silent: Bool = false,
                 locked: Bool = false, _ time: TimeInterval) -> Bool {
    g.v.observe(deviceID: id, state: s, proximityEnabled: prox, silent: silent, screenLocked: locked, at: at(time))
}

@Test func baglantiGecisindeKartCikar() {
    let g = gate()
    #expect(!obs(g, .bagliDegil, 10))
    #expect(obs(g, .bagliBuMac, 11))
    #expect(!obs(g, .bagliBuMac, 12))   // ayni durum tekrar tetiklemez
}

@Test func yakindanBaglanincaDaCikar() {
    let g = gate()
    _ = obs(g, .yakinda, 10)
    #expect(obs(g, .bagliBuMac, 11))
}

@Test func acilistaZatenBagliOlanIcinCikmaz() {
    let g = gate()
    #expect(!obs(g, .bagliBuMac, 10))        // ilk gorulen durum
    let h = gate()
    _ = obs(h, .bilinmiyor, 0)
    #expect(!obs(h, .bagliBuMac, 10))        // bilinmiyor -> bagli acilis sayilir
}

@Test func acilisTamponuIcindeCikmaz() {
    let g = gate()
    _ = obs(g, .bagliDegil, 1)
    #expect(!obs(g, .bagliBuMac, 2))
}

@Test func telefondanGecisteCikmaz() {
    let g = gate()
    _ = obs(g, .bagliTelefon, 10)
    #expect(!obs(g, .bagliBuMac, 11))
}

@Test func ayarKapaliSessizVeKilitteCikmaz() {
    for (prox, silent, locked) in [(false, false, false), (true, true, false), (true, false, true)] {
        let g = gate()
        _ = obs(g, .bagliDegil, 10)
        #expect(!obs(g, .bagliBuMac, prox: prox, silent: silent, locked: locked, 11))
    }
}

@Test func kopupHemenBaglanincaTekrarCikmaz() {
    let g = gate()
    _ = obs(g, .bagliDegil, 10)
    #expect(obs(g, .bagliBuMac, 11))
    _ = obs(g, .bagliDegil, 12)
    #expect(!obs(g, .bagliBuMac, 13))        // bekleme suresi icinde
    _ = obs(g, .bagliDegil, 20)
    #expect(obs(g, .bagliBuMac, 22))
}

@Test func cihazlarAyriSayilir() {
    let g = gate()
    _ = obs(g, .bagliDegil, id: "a", 10)
    _ = obs(g, .bagliDegil, id: "b", 10)
    #expect(obs(g, .bagliBuMac, id: "a", 11))
    #expect(obs(g, .bagliBuMac, id: "b", 11))
}
