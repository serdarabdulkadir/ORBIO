import Testing
import Foundation
@testable import EkosistemCore

@Suite("QCY protokolu")
struct QcyProtocolTests {
    // MeloBuds Pro'dan alinan gercek reklam paketi.
    static let real: [UInt8] = [0x1C, 0x52, 0x4D, 0x4A, 0xEA, 0x00, 0x6E, 0x64, 0x5F, 0x00,
                                0x85, 0xB8, 0x7C, 0xAC, 0x84, 0x60, 0x3A, 0x9D, 0x20, 0x00,
                                0xAC, 0x84, 0x60, 0x59, 0xA2, 0x21]

    @Test func gercekPaketPilVeAdres() {
        let a = QcyAdvertisement.parse(manufacturerData: Self.real)
        #expect(a?.left == 100)
        #expect(a?.right == 95)
        #expect(a?.caseLevel == nil)
        #expect(a?.controlAddress == "84:AC:60:20:9D:3A")
        #expect(a?.leftCharging == false)
    }

    @Test func sarjBayragi() {
        var p = Self.real; p[7] = 0x80 | 40
        #expect(QcyAdvertisement.parse(manufacturerData: p)?.left == 40)
        #expect(QcyAdvertisement.parse(manufacturerData: p)?.leftCharging == true)
    }

    @Test func baskaSirketVeKisaPaketReddedilir() {
        #expect(QcyAdvertisement.parse(manufacturerData: [0x4C, 0x00, 1, 2, 3, 4, 5, 6, 7, 8]) == nil)
        #expect(QcyAdvertisement.parse(manufacturerData: [0x1C, 0x52, 1]) == nil)
    }

    @Test func komutCercevesi() {
        #expect(QcyPacket.request(opcode: 0x17) == [0xFF, 0x03, 0xFE, 0x01, 0x17])
        #expect(QcyNoise.setMode(.gurultuEngeli) == [0xFF, 0x05, 0x17, 0x03, 0x01, 0x05, 0x00])
        #expect(QcyNoise.setMode(.uyarlanir) == nil)
    }

    @Test func yanitAyristirma() {
        let blocks = QcyPacket.parse([0xFF, 0x05, 0x17, 0x03, 0x01, 0x03, 0x02])
        #expect(blocks.count == 1)
        #expect(blocks[0].opcode == 0x17)
        #expect(QcyNoise.parseMode(blocks[0].parameters) == .gurultuEngeli)
        #expect(QcyPacket.parse([0xFF, 0x09, 0x17]).isEmpty)
    }

    @Test func gercekAncYanitiSahne() {
        let b = QcyPacket.parse([0xFF, 0x05, 0x17, 0x03, 0x01, 0x05, 0x00])[0]
        var st = QcyDeviceState()
        let changed = st.apply(opcode: b.opcode, parameters: b.parameters)
        #expect(changed)
        #expect(st.mode == .gurultuEngeli)
        #expect(st.scene == .uyarlanir)
    }

    @Test func sahnePaketleri() {
        #expect(QcyNoiseScene.kapaliAlan.packet == [0xFF, 0x05, 0x17, 0x03, 0x01, 0x01, 0x02])
        #expect(QcyNoiseScene.yolculuk.packet == [0xFF, 0x05, 0x17, 0x03, 0x01, 0x02, 0x02])
        #expect(QcyNoiseScene.gurultulu.packet == [0xFF, 0x05, 0x17, 0x03, 0x01, 0x03, 0x02])
        #expect(QcyNoiseScene.ruzgarKarsiti.packet == [0xFF, 0x05, 0x17, 0x03, 0x01, 0x04, 0x00])
        for s in QcyNoiseScene.allCases { #expect(QcyNoiseScene.parse(Array(s.packet.dropFirst(4))) == s) }
        #expect(QcyNoiseScene.parse([0x01, 0x09, 0x00]) == nil)
        #expect(QcyNoiseScene.parse([0x01, 0x05, 0x02]) == nil)
        #expect(QcyNoiseScene.parse([0x03, 0x01, 0x04]) == nil)
    }

    @Test func seffafVeKapaliSahnesizdir() {
        var st = QcyDeviceState(mode: .gurultuEngeli, scene: .yolculuk)
        st.apply(opcode: 0x17, parameters: [0x03, 0x01, 0x04])
        #expect(st.mode == .seffaf)
        #expect(st.scene == nil)
    }

    @Test func gercekKulakAlgilamaYaniti() {
        let off = QcyWearingDetection.parse([0x00, 0x01, 0x01, 0x00])
        #expect(off == QcyWearingDetection(enabled: false, musicAction: 1, ancAction: 1, toneEnabled: false))
        let note = QcyWearingDetection.parse([0x00, 0x01, 0x01, 0x01])
        #expect(note?.toneEnabled == true)
        #expect(QcyWearingDetection.parse([0x01, 0x01, 0x01])?.toneEnabled == nil)
        #expect(QcyWearingDetection.parse([0x07, 0x01, 0x01]) == nil)
        #expect(QcyWearingDetection.parse([0x01, 0x01]) == nil)
    }

    @Test func kulakAlgilamaYazmaDigerBaytlariKorur() {
        let w = QcyWearingDetection(enabled: false, musicAction: 1, ancAction: 1, toneEnabled: false)
        #expect(w.setEnabledPacket(true) == [0xFF, 0x06, 0x2C, 0x04, 0x01, 0x01, 0x01, 0x02])
        let n = QcyWearingDetection(enabled: true, musicAction: 1, ancAction: 1, toneEnabled: nil)
        #expect(n.setEnabledPacket(false) == [0xFF, 0x05, 0x2C, 0x03, 0x02, 0x01, 0x01])
    }

    @Test func okunmamisDurumdaKulakAlgilamaYazilmaz() {
        #expect(QcyCommand.wearingDetection(true).packet(state: QcyDeviceState()) == nil)
        var st = QcyDeviceState()
        st.apply(opcode: 0x2C, parameters: [0x00, 0x01, 0x01, 0x00])
        #expect(QcyCommand.wearingDetection(true).packet(state: st) != nil)
        #expect(st.applying(.wearingDetection(true)).wearing?.enabled == true)
        #expect(QcyCommand.wearingDetection(true).readbackOpcode == 0x2C)
        #expect(QcyCommand.scene(.gurultulu).readbackOpcode == 0x17)
    }

    @Test func ciftCihazPaketi() {
        #expect(QcyCommand.multipoint(true).packet(state: QcyDeviceState()) == [0xFF, 0x03, 0x24, 0x01, 0x01])
        #expect(QcyCommand.multipoint(false).packet(state: QcyDeviceState()) == [0xFF, 0x03, 0x24, 0x01, 0x02])
        #expect(QcyPacket.request(opcode: 0x24) == [0xFF, 0x03, 0xFE, 0x01, 0x24])
        #expect(QcyCommand.multipoint(true).readbackOpcode == 0x24)
        #expect(QcyCommand.multipoint(true).verifiedByReadback)
        #expect(!QcyCommand.multipoint(true).writesKeyMap)
    }

    @Test func ciftCihazYanitiVeDurum() {
        var st = QcyDeviceState()
        #expect(st.multipoint == nil)
        do { let r = st.apply(opcode: 0x24, parameters: [0x00]); #expect(r) }
        #expect(st.multipoint == false)
        do { let r = st.apply(opcode: 0x24, parameters: [0x01]); #expect(r) }
        #expect(st.multipoint == true)
        st.apply(opcode: 0x24, parameters: [0x02])
        #expect(st.multipoint == false)
        do { let r = st.apply(opcode: 0x24, parameters: [0x07]); #expect(!r) }
        do { let r = st.apply(opcode: 0x24, parameters: []); #expect(!r) }
        #expect(st.multipoint == false)
        // Gercek yanit paketi: FF 03 24 01 00
        let b = QcyPacket.parse([0xFF, 0x03, 0x24, 0x01, 0x00])[0]
        #expect(b.opcode == 0x24 && b.parameters == [0x00])
        #expect(st.applying(.multipoint(true)).multipoint == true)
    }

    @Test func ciftCihazYazmaSonrasiDogrulama() {
        var st = QcyDeviceState(multipoint: false)
        let cmd = QcyCommand.multipoint(true)
        #expect(!cmd.isSatisfied(by: st))        // cihaz degistirmedi
        st.apply(opcode: 0x24, parameters: [0x01])
        #expect(cmd.isSatisfied(by: st))
        #expect(!QcyCommand.multipoint(true).isSatisfied(by: QcyDeviceState()))
    }

    static let realKeys: [UInt8] = [0x01, 0x00, 0x02, 0x00, 0x03, 0x01, 0x04, 0x01, 0x05, 0x04,
                                    0x06, 0x03, 0x07, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00]

    @Test func gercekTusEslemesiAyristirma() {
        let k = QcyKeyMap(bytes: Self.realKeys)
        #expect(k != nil)
        #expect(k?.function(side: .left, gesture: .double) == .playPause)
        #expect(k?.function(side: .right, gesture: .double) == .playPause)
        // eventID 1...6 (tek / cift / uc, sol / sag) cihazda var; 7 (islev 0) taninmaz.
        #expect(k?.function(side: .left, gesture: .triple) == .voiceAssistant)
        #expect(k?.function(side: .right, gesture: .triple) == .next)
        #expect(k?.function(side: .left, gesture: .single) == QcyKeyFunction.none)
        #expect(k?.slots.count == 6)
        #expect(QcyKeyMap(bytes: []) == nil)
        #expect(QcyKeyMap(bytes: [0x03, 0x01, 0x04]) == nil)
        var st = QcyDeviceState()
        do { let r = st.apply(keyMapBytes: Self.realKeys); #expect(r) }
        do { let r = st.apply(keyMapBytes: Self.realKeys); #expect(!r) }
        #expect(st.keys?.bytes == Self.realKeys)
        do { let r = st.apply(opcode: 0x2B, parameters: [0x03, 0x03, 0x04, 0x02]); #expect(r) }
        #expect(st.keys?.function(side: .right, gesture: .double) == .previous)
    }

    @Test func tusYazmaPaketiDigerAnahtarlariKorur() throws {
        var st = QcyDeviceState()
        st.apply(keyMapBytes: Self.realKeys)
        let cmd = QcyCommand.touch(.right, .double, .next)
        let packet = try #require(cmd.packet(state: st))
        var expected = Self.realKeys
        expected[7] = 0x03               // yalnizca 0x04 anahtarinin islevi
        #expect(packet == expected)
        #expect(packet.count == 20)
        #expect(cmd.writesKeyMap && cmd.verifiedByReadback)
        // Okunmamis durumda ya da cihazda olmayan jestte yazilmaz.
        #expect(cmd.packet(state: QcyDeviceState()) == nil)
        #expect(QcyCommand.touch(.left, .double, .next).packet(state: QcyDeviceState(keys: QcyKeyMap(bytes: [0x09, 0x00]))) == nil)
        #expect(st.applying(cmd).keys?.bytes == expected)
        #expect(cmd.isSatisfied(by: st.applying(cmd)))
        #expect(!cmd.isSatisfied(by: st))
    }

    @Test func tusEslemesiniOncekiDegereDondur() throws {
        var st = QcyDeviceState()
        st.apply(keyMapBytes: Self.realKeys)
        let original = try #require(st.keys)
        let changed = st.applying(.touch(.left, .double, .volumeUp))
        #expect(changed.keys != original)
        let restore = QcyCommand.keys(original)
        #expect(restore.packet(state: changed) == Self.realKeys)
        #expect(changed.applying(restore).keys == original)
    }

    @Test func seffafSeviyePaketiVeSinirlama() {
        #expect(QcyCommand.transparencyLevel(4).packet(state: QcyDeviceState()) == [0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x04])
        #expect(QcyTransparency.packet(level: 0) == [0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x01])
        #expect(QcyTransparency.packet(level: 99) == [0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x08])
        #expect(QcyTransparency.packet(level: 8).last == 8)
        #expect(QcyCommand.transparencyLevel(2).readbackOpcode == 0x17)
        #expect(QcyCommand.transparencyLevel(2).verifiedByReadback)
        #expect(QcyNoise.setMode(.seffaf) == QcyTransparency.packet(level: QcyTransparency.defaultLevel))
    }

    @Test func gercekSeffafYanitiSeviyeyiAyristirir() {
        let b = QcyPacket.parse([0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x04])[0]
        var st = QcyDeviceState()
        let changed = st.apply(opcode: b.opcode, parameters: b.parameters)
        #expect(changed)
        #expect(st.mode == .seffaf)
        #expect(st.transparencyLevel == 4)
        st.apply(opcode: 0x17, parameters: [0x03, 0x01, 0x06])
        #expect(st.transparencyLevel == 6)
        st.apply(opcode: 0x17, parameters: [0x02, 0x00, 0x00])
        #expect(st.transparencyLevel == nil)
        #expect(QcyTransparency.parseLevel([0x01, 0x05, 0x00]) == nil)
    }

    @Test func seffafSeviyeDogrulamaVeUygulama() {
        let cmd = QcyCommand.transparencyLevel(7)
        var st = QcyDeviceState(mode: .seffaf, transparencyLevel: 4)
        #expect(!cmd.isSatisfied(by: st))
        st.apply(opcode: 0x17, parameters: [0x03, 0x01, 0x07])
        #expect(cmd.isSatisfied(by: st))
        #expect(QcyDeviceState(mode: .kapali).applying(.transparencyLevel(30)).transparencyLevel == 8)
    }

    @Test func oyunModuPaketiVeCozum() {
        #expect(QcyGameMode.packet(enabled: true) == [0xFF, 0x03, 0x09, 0x01, 0x01])
        #expect(QcyGameMode.packet(enabled: false) == [0xFF, 0x03, 0x09, 0x01, 0x02])
        #expect(QcyGameMode.parse([0x01]) == true)
        #expect(QcyGameMode.parse([0x02]) == false)
        #expect(QcyGameMode.parse([0x07]) == nil)
        var st = QcyDeviceState()
        let applied = st.apply(opcode: 0x09, parameters: [0x01])
        #expect(applied)
        #expect(st.gameMode == true)
    }

    @Test func kulakAlgilamaAcKapa() {
        #expect(QcyEarDetection.packet(enabled: true) == [0xFF, 0x03, 0x06, 0x01, 0x01])
        #expect(QcyEarDetection.packet(enabled: false) == [0xFF, 0x03, 0x06, 0x01, 0x02])
        var st = QcyDeviceState()
        st.apply(opcode: 0x06, parameters: [0x02])
        #expect(st.earDetection == false)
        #expect(st.wearing == nil)
    }

    @Test func eqOnAyari() {
        #expect(QcyEqPreset(index: 6) == nil)
        #expect(QcyEqPreset(index: -1) == nil)
        #expect(QcyEqPreset.all.count == 6)
        #expect(QcyEqPreset.all.map(\.name) == ["Varsayılan", "Pop", "Bas", "Rock", "Yumuşak", "Klasik"])
        #expect(QcyEqPreset(index: 2)?.bands == [8, 7, 5, 4, 0, 0, 0, 0, 0, 0])
        #expect(QcyEqPreset(index: 2)?.packet.count == 77)
        #expect(QcyEqPreset(index: 2)?.packet[4] == 0x02)
        #expect(QcyEqPreset(index: 5)?.legacyPayload == [5, 6, 7, 1, 2, 0xFF, 1, 0xFC, 0xFA, 0xF9, 0xF8])
        #expect(QcyEqPreset.parse([0x05] + [UInt8](repeating: 0, count: 142))?.index == 5)
        #expect(QcyEqPreset.parse([0xFF]) == nil)
        #expect(QcyEqPreset.parse([]) == nil)
        var st = QcyDeviceState()
        st.apply(opcode: 0x22, parameters: [0x02])
        #expect(st.eqPreset?.index == 2)
    }

    @Test func yetenekDogrulamasi() {
        #expect(QcyCapability.verified == [.gameMode, .earDetection])
        #expect(QcyCapability.eqPreset.isEnabled && QcyCapability.eqCustom.isEnabled && QcyCapability.touchControls.isEnabled)
        #expect(!QcyCapability.multipoint.isEnabled)
        #expect(!QcyCapability.eqCustom.isVerified)
        #expect(!QcyCapability.transparencyLevels.isVerified)
        #expect(!QcyCapability.multipoint.isVerified)
        #expect(Device(id: "a", name: "b", profile: .tws).isQcyVerified(.gameMode))
        #expect(!Device(id: "a", name: "b", profile: .apple).isQcyVerified(.gameMode))
        #expect(Device(id: "a", name: "b", profile: .tws).verifiedQcyCapabilities == [.gameMode, .earDetection])
        #expect(Device(id: "a", name: "b", profile: .tws).isQcyEnabled(.eqCustom))
        #expect(!Device(id: "a", name: "b", profile: .tws).isQcyVerified(.eqCustom))
        #expect(!Device(id: "a", name: "b", profile: .apple).isQcyEnabled(.eqCustom))
    }

    @Test func genisletilmisKomutlar() {
        let empty = QcyDeviceState()
        #expect(QcyCommand.gameMode(true).packet(state: empty) == [0xFF, 0x03, 0x09, 0x01, 0x01])
        #expect(QcyCommand.earDetection(false).packet(state: empty) == [0xFF, 0x03, 0x06, 0x01, 0x02])
        let eq3 = QcyEqPreset(index: 3)!
        #expect(QcyCommand.eqPreset(eq3).packet(state: empty) == eq3.packet)
        #expect(QcyCommand.gameMode(true).readbackOpcode == 0x09)
        #expect(QcyCommand.earDetection(true).readbackOpcode == 0x06)
        #expect(QcyCommand.eqPreset(eq3).readbackOpcode == 0x22)
        #expect(!QcyCommand.gameMode(true).writesKeyMap)
        let s = empty.applying(.gameMode(true)).applying(.earDetection(false)).applying(.eqPreset(eq3))
        #expect(s.gameMode == true && s.earDetection == false && s.eqPreset == eq3)
        #expect(QcyCommand.gameMode(true).isSatisfied(by: s))
        #expect(QcyCommand.earDetection(false).isSatisfied(by: s))
        #expect(QcyCommand.eqPreset(eq3).isSatisfied(by: s))
        #expect(!QcyCommand.gameMode(false).isSatisfied(by: s))
        #expect(!QcyCommand.eqPreset(eq3).isSatisfied(by: empty))
    }

    @Test func dokunusEventIDVePaketi() {
        #expect(QcyTouchKeys.eventID(side: .left, gesture: .single) == 1)
        #expect(QcyTouchKeys.eventID(side: .right, gesture: .single) == 2)
        #expect(QcyTouchKeys.eventID(side: .left, gesture: .double) == 3)
        #expect(QcyTouchKeys.eventID(side: .right, gesture: .double) == 4)
        #expect(QcyTouchKeys.eventID(side: .left, gesture: .triple) == 5)
        #expect(QcyTouchKeys.eventID(side: .right, gesture: .triple) == 6)
        #expect(QcyTouchKeys.packet(side: .left, gesture: .double, function: .playPause) == [0x03, 0x01])
        #expect(QcyTouchKeys.packet(side: .right, gesture: .triple, function: .voiceAssistant) == [0x06, 0x04])
        #expect(QcyTouchKeys.slot(eventID: 7) == nil)
        #expect(QcyKeyFunction.allCases.map(\.rawValue) == Array(0...7))
    }

    @Test func ozelEqPaketiTestVektoru() {
        let zero = QcyCustomEq.packets(gains: [])
        #expect(zero.count == 1)
        let p = zero[0]
        #expect(Array(p.prefix(7)) == [0xFF, 0x4B, 0x22, 0x49, 0xFF, 0x00, 0x00])
        #expect(p.count == 77)
        // ilk bant: 31 Hz, 0 dB, Q 1.00, tur 255
        #expect(Array(p[7..<14]) == [0x1F, 0x00, 0x00, 0x00, 0x64, 0x00, 0xFF])
        // son bant: 16 kHz
        #expect(Array(p[70..<72]) == [0x80, 0x3E])
        // +8 / -8 dB ve sinirlama
        let g = QcyCustomEq.packets(gains: [8, -8, 99])[0]
        #expect(Array(g[9..<11]) == [0x20, 0x03])
        #expect(Array(g[16..<18]) == [0xE0, 0xFC])
        #expect(Array(g[23..<25]) == [0x20, 0x03])
        // eski 6 baytlik bant (0x20)
        let old = QcyCustomEq.packets(gains: [], format: .multiEq)[0]
        #expect(Array(old.prefix(4)) == [0xFF, 0x41, 0x20, 0x3F])
        #expect(old.count == 67)
        #expect(QcyCommand.customEq([8]).packet(state: QcyDeviceState()) == QcyCustomEq.packets(gains: [8])[0])
        #expect(!QcyCommand.customEq([]).verifiedByReadback && QcyCommand.customEq([]).readbackOpcode == 0x22)
    }
}
