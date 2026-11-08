import Testing
@testable import EkosistemCore

// Sentetik vektorler (gercek cihaz kaydi degil). Kendi cihaz kaydi alininca buraya eklenecek.
private func frame(model: UInt16, status: UInt8, battery: UInt8, charge: UInt8, lid: UInt8 = 0x31, color: UInt8 = 0x00) -> [UInt8] {
    var d: [UInt8] = [0x4C, 0x00, 0x07, 0x19, 0x01, UInt8(model >> 8), UInt8(model & 0xFF), status, battery, charge, lid, color, 0x00]
    d += [UInt8](repeating: 0xAA, count: 16) // sifreli kisim: dokunulmaz
    return d
}

@Test func cozucuTemelAlanlar() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x2014, status: 0x55, battery: 0x89, charge: 0x46)))
    #expect(info.modelName == "AirPods Pro (2. nesil)")
    #expect(info.left == .percent(80))
    #expect(info.right == .percent(90))
    #expect(info.caseBattery == .percent(60))
    #expect(info.caseCharging)
    #expect(info.lidCounter == 0x31)
}

@Test func cevirmeBitiSolSagiDegistirir() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x200E, status: 0x75, battery: 0x89, charge: 0x2F)))
    #expect(info.left == .percent(90))
    #expect(info.right == .percent(80))
    #expect(info.caseBattery == .unknown)
    #expect(info.rightCharging)
    #expect(!info.leftCharging)
}

@Test func bilinmeyenPilNibble() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x1234, status: 0x01, battery: 0xF5, charge: 0x0F)))
    #expect(info.modelName == nil)
    #expect(info.left == .unknown)
    #expect(info.right == .percent(50))
}

@Test func baskaSirketVeKisaVeriReddedilir() {
    var d = frame(model: 0x2014, status: 0x55, battery: 0x89, charge: 0x46)
    d[0] = 0x06
    #expect(ProximityPairingParser.parse(manufacturerData: d) == nil)
    #expect(ProximityPairingParser.parse(manufacturerData: [0x4C, 0x00, 0x07, 0x19, 0x01]) == nil)
    #expect(ProximityPairingParser.parse(manufacturerData: [0x4C]) == nil)
}

@Test func onundeBaskaTLVOlanYuk() throws {
    // Once 0x10 (Nearby Info) TLV, sonra 0x07.
    let pp = Array(frame(model: 0x2014, status: 0x55, battery: 0x77, charge: 0x05).dropFirst(2))
    let d: [UInt8] = [0x4C, 0x00, 0x10, 0x02, 0x0B, 0x1C] + pp
    let info = try #require(ProximityPairingParser.parse(manufacturerData: d))
    #expect(info.left == .percent(70))
}
