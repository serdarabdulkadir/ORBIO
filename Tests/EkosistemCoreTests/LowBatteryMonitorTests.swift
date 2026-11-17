import Testing
import Foundation
@testable import EkosistemCore

private func obs(_ m: Box<LowBatteryMonitor>, _ r: BatteryReading, id: String = "d", _ time: TimeInterval = 0) -> [LowBatteryAlert] {
    m.v.observe(deviceID: id, reading: r, at: at(time))
}

@Test func yirmideBirKezUyarir() {
    let m = Box(LowBatteryMonitor())
    #expect(obs(m, reading(l: 21)).isEmpty)
    #expect(obs(m, reading(l: 20)) == [LowBatteryAlert(deviceID: "d", channel: .sol, percent: 20)])
    #expect(obs(m, reading(l: 19)).isEmpty)
    #expect(obs(m, reading(l: 10)).isEmpty)
}

@Test func yirmiBesinUstuneCikmadanTekrarYok() {
    let m = Box(LowBatteryMonitor())
    _ = obs(m, reading(l: 15))
    #expect(obs(m, reading(l: 25)).isEmpty)
    #expect(obs(m, reading(l: 18)).isEmpty)   // 25'e cikti ama ustune degil
    #expect(obs(m, reading(l: 26)).isEmpty)
    #expect(obs(m, reading(l: 20)).count == 1)  // yeniden kuruldu
}

@Test func solSagKutuAyriIzlenir() {
    let m = Box(LowBatteryMonitor())
    #expect(obs(m, reading(l: 15, r: 50, c: 90)).map(\.channel) == [.sol])
    #expect(obs(m, reading(l: 15, r: 12, c: 90)).map(\.channel) == [.sag])
    #expect(obs(m, reading(l: 15, r: 12, c: 5)).map(\.channel) == [.kutu])
}

@Test func sarjdaykenUyarmaz() {
    let m = Box(LowBatteryMonitor())
    #expect(obs(m, reading(l: 10, lc: true)).isEmpty)
    #expect(obs(m, reading(c: 10, cc: true)).isEmpty)
    // sarj bitince (hala dusukse) uyarir
    #expect(obs(m, reading(l: 10, lc: false)).count == 1)
}

@Test func bilinmeyenDegerUyarmazVeDurumuBozmaz() {
    let m = Box(LowBatteryMonitor())
    _ = obs(m, reading(l: 10))
    #expect(obs(m, reading(l: nil)).isEmpty)
    #expect(obs(m, reading(l: 10)).isEmpty)
}

@Test func soluklukOkumaUyariUretmez() {
    let m = Box(LowBatteryMonitor())
    #expect(obs(m, reading(l: 5, time: at(0)), 31 * 60).isEmpty)
}

@Test func cihazlarAyriVeUnutmaSifirlar() {
    let m = Box(LowBatteryMonitor())
    #expect(obs(m, reading(l: 10), id: "a").count == 1)
    #expect(obs(m, reading(l: 10), id: "b").count == 1)
    m.v.reset(deviceID: "a")
    #expect(obs(m, reading(l: 10), id: "a").count == 1)
    #expect(obs(m, reading(l: 10), id: "b").isEmpty)
}

@Test func tekDegerliGenelPilIzlenir() {
    let m = Box(LowBatteryMonitor())
    #expect(obs(m, reading(overall: 15, source: .standart)).map(\.channel) == [.genel])
}
