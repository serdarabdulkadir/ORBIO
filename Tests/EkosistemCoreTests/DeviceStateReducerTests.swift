import Testing
import Foundation
@testable import EkosistemCore

@Test func ilkAndaBilinmiyorSonraBagliDegil() {
    let r = DeviceStateReducer(startedAt: t0)
    #expect(r.state(at: at(0)) == .bilinmiyor)
    #expect(r.state(at: at(59)) == .bilinmiyor)
    #expect(r.state(at: at(60)) == .bagliDegil)
}

@Test func reklamYakindaYapar10SnSonraBiter() {
    var r = DeviceStateReducer(startedAt: t0)
    r.recordAdvertisement(at: at(5))
    #expect(r.state(at: at(5)) == .yakinda)
    #expect(r.state(at: at(14.9)) == .yakinda)
    #expect(r.state(at: at(15)) == .bilinmiyor)   // sinyal yok: once bilinmiyor
    #expect(r.state(at: at(65)) == .bagliDegil)   // sonra bagli degil
}

@Test func baglantiBilgisiReklamdanUstun() {
    var r = DeviceStateReducer(startedAt: t0)
    r.recordAdvertisement(at: at(1))
    r.setConnection(.buMac, at: at(2))
    #expect(r.state(at: at(3)) == .bagliBuMac)
    #expect(r.state(at: at(500)) == .bagliBuMac)  // olay tabanli: bayatlamaz
    r.setConnection(.telefon, at: at(501))
    #expect(r.state(at: at(502)) == .bagliTelefon)
}

@Test func kopanBaglantiReklamVarsaYakinda() {
    var r = DeviceStateReducer(startedAt: t0)
    r.setConnection(.buMac, at: at(1))
    r.setConnection(.degil, at: at(2))
    #expect(r.state(at: at(3)) == .bagliDegil)
    r.recordAdvertisement(at: at(4))
    #expect(r.state(at: at(5)) == .yakinda)
    #expect(r.state(at: at(20)) == .bagliDegil)
}

@Test func pilKaynakOnceligi() {
    var r = DeviceStateReducer(startedAt: t0)
    r.updateBattery(reading(overall: 50, source: .standart, time: at(0)))
    #expect(r.battery?.overall == 50)
    r.updateBattery(reading(l: 80, r: 70, source: .markaOzel, time: at(10)))
    #expect(r.battery?.source == .markaOzel)
    // dusuk oncelikli yeni okuma taze markaOzel okumayi ezmez
    r.updateBattery(reading(overall: 30, source: .standart, time: at(20)))
    #expect(r.battery?.source == .markaOzel)
    // markaOzel okuma soluklasinca standart kabul edilir
    r.updateBattery(reading(overall: 30, source: .standart, time: at(10 + 31 * 60)))
    #expect(r.battery?.source == .standart)
    // ayni oncelikte yeni olan kazanir; eski olan kazanmaz
    r.updateBattery(reading(overall: 35, source: .standart, time: at(10 + 32 * 60)))
    #expect(r.battery?.overall == 35)
    r.updateBattery(reading(overall: 99, source: .standart, time: at(0)))
    #expect(r.battery?.overall == 35)
}

@Test func bosYokOkumaKabulEdilmez() {
    var r = DeviceStateReducer(startedAt: t0)
    r.updateBattery(reading(source: .yok))
    #expect(r.battery == nil)
}
