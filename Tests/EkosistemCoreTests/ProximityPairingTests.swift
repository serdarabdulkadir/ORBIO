import Testing
@testable import EkosistemCore

// Sentetik vektorler (gercek cihaz kaydi degil). Kendi cihaz kaydi alininca buraya eklenecek.
private func frame(model: UInt16, status: UInt8, battery: UInt8, charge: UInt8, lid: UInt8 = 0x31, color: UInt8 = 0x00) -> [UInt8] {
    var d: [UInt8] = [0x4C, 0x00, 0x07, 0x19, 0x01, UInt8(model >> 8), UInt8(model & 0xFF), status, battery, charge, lid, color, 0x00]
    d += [UInt8](repeating: 0xAA, count: 16) // sifreli kisim: dokunulmaz
    return d
}

@Test func cozucuTemelAlanlar() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x1420, status: 0x55, battery: 0x89, charge: 0x46)))
    #expect(info.modelName == "AirPods Pro (2. nesil, Lightning)")
    #expect(info.left == .percent(80))
    #expect(info.right == .percent(90))
    #expect(info.caseBattery == .percent(60))
    #expect(info.caseCharging)
    #expect(info.lidCounter == 0x31)
}

@Test func cevirmeBitiSolSagiDegistirir() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x0E20, status: 0x75, battery: 0x89, charge: 0x2F)))
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
    var d = frame(model: 0x1420, status: 0x55, battery: 0x89, charge: 0x46)
    d[0] = 0x06
    #expect(ProximityPairingParser.parse(manufacturerData: d) == nil)
    #expect(ProximityPairingParser.parse(manufacturerData: [0x4C, 0x00, 0x07, 0x19, 0x01]) == nil)
    #expect(ProximityPairingParser.parse(manufacturerData: [0x4C]) == nil)
}

@Test func onundeBaskaTLVOlanYuk() throws {
    // Once 0x10 (Nearby Info) TLV, sonra 0x07.
    let pp = Array(frame(model: 0x1420, status: 0x55, battery: 0x77, charge: 0x05).dropFirst(2))
    let d: [UInt8] = [0x4C, 0x00, 0x10, 0x02, 0x0B, 0x1C] + pp
    let info = try #require(ProximityPairingParser.parse(manufacturerData: d))
    #expect(info.left == .percent(70))
}

// MARK: Model katalogu

@Test func modelKimlikleriBenzersizVeAdli() {
    let ids = AppleModelCatalog.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(AppleModelCatalog.all.count >= 30)
    #expect(AppleModelCatalog.all.allSatisfy { !$0.name.isEmpty })
    #expect(ProximityPairingParser.knownModels.count == ids.count)
}

@Test func istenenModellerKatalogdaVar() {
    let expected: [(UInt16, String)] = [
        (0x0220, "AirPods (1. nesil)"), (0x0F20, "AirPods (2. nesil)"), (0x1320, "AirPods (3. nesil)"),
        (0x1920, "AirPods 4"), (0x1B20, "AirPods 4 (ANC)"), (0x0E20, "AirPods Pro"),
        (0x1420, "AirPods Pro (2. nesil, Lightning)"), (0x2420, "AirPods Pro (2. nesil, USB-C)"),
        (0x2720, "AirPods Pro 3"), (0x0A20, "AirPods Max (Lightning)"), (0x1F20, "AirPods Max (USB-C)"),
        (0x0320, "Powerbeats3"), (0x0520, "BeatsX"), (0x0620, "Beats Solo3"), (0x0B20, "Powerbeats Pro"),
        (0x0C20, "Beats Solo Pro"), (0x1120, "Beats Studio Buds"), (0x1620, "Beats Studio Buds+"),
        (0x1220, "Beats Fit Pro"), (0x1020, "Beats Flex"), (0x2620, "Beats Solo Buds"),
    ]
    for (id, name) in expected {
        #expect(AppleModelCatalog.model(forID: id)?.name == name)
    }
}

@Test func yetenekMatrisiOrnekleri() throws {
    let pro2 = try #require(AppleModelCatalog.model(forID: 0x2420))
    #expect(pro2.listeningModes == [.kapali, .gurultuEngeli, .seffaf, .uyarlanir])
    #expect(pro2.supports(.conversationAwareness) && pro2.supports(.adaptiveStrength) && pro2.hasCase)
    #expect(pro2.form == .trueWireless && pro2.aapVerification == .dogrulandiKaynak)

    let pro1 = try #require(AppleModelCatalog.model(forID: 0x0E20))
    #expect(pro1.listeningModes == [.kapali, .gurultuEngeli, .seffaf])
    #expect(!pro1.supports(.adaptive) && !pro1.supports(.conversationAwareness))

    let gen2 = try #require(AppleModelCatalog.model(forID: 0x0F20))
    #expect(gen2.listeningModes.isEmpty)
    #expect(gen2.supports(.earDetection) && !gen2.supports(.noiseControl))

    let maxM = try #require(AppleModelCatalog.model(forID: 0x0A20))
    #expect(maxM.form == .headset && !maxM.hasCase && maxM.supports(.noiseControl))

    let pbp = try #require(AppleModelCatalog.model(forID: 0x0B20))
    #expect(pbp.family == .beats && pbp.hasCase && pbp.listeningModes.isEmpty)
}

@Test func modelNumarasindanModelBulunur() {
    #expect(AppleModelCatalog.model(forModelNumber: "A3048")?.id == 0x2420)
    #expect(AppleModelCatalog.model(forModelNumber: " a2096 ")?.id == 0x0A20)
    #expect(AppleModelCatalog.model(forModelNumber: "") == nil)
    #expect(AppleModelCatalog.model(forModelNumber: "A0000") == nil)
}

@Test func bilinmeyenModelKimligiAdsiz() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x7F7F, status: 0x01, battery: 0x55, charge: 0x05)))
    #expect(info.modelInfo == nil)
    #expect(info.modelName == nil)
}

@Test func kulakBitleriVeKutuBiti() throws {
    // bit3 tek, cevirme (bit5) yok, kutuda degil: sol kulakta.
    var info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x0E20, status: 0x08, battery: 0x55, charge: 0x05)))
    #expect(info.leftInEar && !info.rightInEar)
    // bit5 + bit3: sag kulakta.
    info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x0E20, status: 0x28, battery: 0x55, charge: 0x05)))
    #expect(!info.leftInEar && info.rightInEar)
    // bit6 (yayinlayan kutuda) cevirmeyi tersler.
    info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x0E20, status: 0x48, battery: 0x55, charge: 0x05)))
    #expect(!info.leftInEar && info.rightInEar)
    // kutu bitleri
    info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x0E20, status: 0x14, battery: 0x55, charge: 0x05)))
    #expect(info.onePodInCase && info.bothPodsInCase)
}

@Test func tekParcaCihazPiliAltNibbledan() throws {
    let info = try #require(ProximityPairingParser.parse(manufacturerData: frame(model: 0x0A20, status: 0x20, battery: 0xF7, charge: 0x1F)))
    #expect(info.modelInfo?.form == .headset)
    #expect(info.headsetBattery == .percent(70))
    #expect(info.headsetCharging)
    #expect(info.headsetWorn)
}
