import Testing
import Foundation
@testable import EkosistemCore

@Test func pilOkumasi30DkdanEskiyseSoluk() {
    let r = reading(l: 80, r: 80, time: t0)
    #expect(!r.isStale(at: at(30 * 60)))      // tam 30 dk: henuz soluk degil
    #expect(r.isStale(at: at(30 * 60 + 1)))
    #expect(!r.isStale(at: at(0)))
}

@Test func reklamdanPilOkumasiBilinmeyenNil() throws {
    var data: [UInt8] = [0x4C, 0x00, 0x07, 0x19, 0x01, 0x20, 0x14, 0x55, 0x8F, 0x46, 0x31, 0x00, 0x00]
    data += [UInt8](repeating: 0xAA, count: 16)
    let info = try #require(ProximityPairingParser.parse(manufacturerData: data))
    let r = BatteryReading(info: info, at: t0)
    #expect(r.left == 80)
    #expect(r.right == nil)
    #expect(r.caseLevel == 60)
    #expect(r.source == .markaOzel)
    #expect(r.hasAnyValue)
}

@Test func bosOkumaDegerYok() {
    #expect(!reading(source: .yok).hasAnyValue)
}

@Test func genelPilDusukPilKanaliSarjiBirlestirir() {
    let r = reading(overall: 40, lc: true)
    #expect(r.level(.genel) == 40)
    #expect(r.isCharging(.genel))
    #expect(!r.isCharging(.sag))
}

@Test func appleProfilindeUyarlanirModuVar() {
    #expect(Device(id: "a", name: "A", profile: .apple).availableListeningModes.contains(.uyarlanir))
    #expect(!Device(id: "b", name: "B", profile: .tws).availableListeningModes.contains(.uyarlanir))
}
