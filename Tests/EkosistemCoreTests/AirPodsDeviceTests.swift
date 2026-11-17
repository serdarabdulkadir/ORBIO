import Testing
import Foundation
@testable import EkosistemCore

private func state(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, mode: ListeningMode? = nil) -> AirPodsDeviceState {
    var s = AirPodsDeviceState()
    var entries: [AAPBatteryEntry] = []
    if let left { entries.append(AAPBatteryEntry(component: .left, percent: left, state: .discharging)) }
    if let right { entries.append(AAPBatteryEntry(component: .right, percent: right, state: .discharging)) }
    if let caseLevel { entries.append(AAPBatteryEntry(component: .caseBox, percent: caseLevel, state: .discharging)) }
    if !entries.isEmpty { s.apply(.battery(entries)) }
    if let mode { s.apply(.listeningMode(mode)) }
    return s
}

// MARK: Device

@Test func appleModelYalnizAppleProfilindeVeKimlikBilinirse() {
    #expect(Device(id: "a", name: "A", profile: .apple, appleModelID: 0x2420).appleModel?.name == "AirPods Pro (2. nesil, USB-C)")
    #expect(Device(id: "b", name: "B", profile: .tws, appleModelID: 0x2420).appleModel == nil)
    #expect(Device(id: "c", name: "C", profile: .apple).appleModel == nil)
    #expect(Device(id: "d", name: "D", profile: .apple, appleModelID: 0x7F7F).appleModel == nil)
}

@Test func modelaGoreDinlemeModlari() {
    // Bilinmeyen Apple modeli: onceki davranis (hepsi).
    #expect(Device(id: "a", name: "A", profile: .apple).availableListeningModes == ListeningMode.allCases)
    // Uyarlanir olan model.
    #expect(Device(id: "b", name: "B", profile: .apple, appleModelID: 0x1420).availableListeningModes == ListeningMode.allCases)
    // Pro 1: uyarlanir yok.
    #expect(Device(id: "c", name: "C", profile: .apple, appleModelID: 0x0E20).availableListeningModes
            == [.kapali, .gurultuEngeli, .seffaf])
    // AirPods 2: ses modu yok.
    #expect(Device(id: "d", name: "D", profile: .apple, appleModelID: 0x0F20).availableListeningModes.isEmpty)
    // Apple disi profil degismedi.
    #expect(Device(id: "e", name: "E", profile: .tws).availableListeningModes == [.kapali, .gurultuEngeli, .seffaf])
}

@Test func yetenekSorgusu() {
    let pro = Device(id: "a", name: "A", profile: .apple, appleModelID: 0x2420)
    #expect(pro.supports(.conversationAwareness) && pro.supports(.caseBattery))
    let max = Device(id: "b", name: "B", profile: .apple, appleModelID: 0x0A20)
    #expect(!max.supports(.caseBattery) && max.supports(.noiseControl))
    #expect(!Device(id: "c", name: "C", profile: .apple).supports(.earDetection))
}

@Test func cihazCodableAirPodsDurumuylaGidisDonus() throws {
    var d = Device(id: "a", name: "A", profile: .apple, appleModelID: 0x1420)
    d.airPods = state(left: 80, right: 70, mode: .seffaf)
    let back = try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(d))
    #expect(back == d)
}

@Test func eskiKayitAppleAlanlariOlmadanCozulur() throws {
    // Alanlar eklenmeden once yazilmis JSON.
    let json = #"{"id":"x","name":"X","profile":"apple","supportsMultipoint":false,"state":"bilinmiyor"}"#
    let d = try JSONDecoder().decode(Device.self, from: Data(json.utf8))
    #expect(d.appleModelID == nil && d.airPods == nil)
}

// MARK: DeviceStateReducer

@Test func reducerAirPodsDurumunuSaklarVePilIsler() {
    var r = DeviceStateReducer(startedAt: t0)
    #expect(r.airPods == nil)
    r.updateAirPods(state(left: 90, right: 80, caseLevel: 50, mode: .gurultuEngeli), at: at(1))
    #expect(r.airPods?.listeningMode == .gurultuEngeli)
    #expect(r.battery?.left == 90 && r.battery?.caseLevel == 50)
    #expect(r.battery?.timestamp == at(1))
}

@Test func reducerAAPPiliReklamPilindenYeniyseUstunGelir() {
    var r = DeviceStateReducer(startedAt: t0)
    r.updateBattery(reading(l: 60, r: 60, c: 40, time: at(1)))
    r.updateAirPods(state(left: 62, right: 61, caseLevel: 40), at: at(5))
    #expect(r.battery?.left == 62)
    // Daha eski zamanli AAP okumasi yeni reklam okumasini ezmez.
    r.updateBattery(reading(l: 70, r: 70, c: 40, time: at(20)))
    r.updateAirPods(state(left: 10, right: 10, caseLevel: 10), at: at(10))
    #expect(r.battery?.left == 70)
}

@Test func reducerPilsizDurumPiliDegistirmez() {
    var r = DeviceStateReducer(startedAt: t0)
    r.updateBattery(reading(l: 55, r: 55, time: at(1)))
    r.updateAirPods(state(mode: .seffaf), at: at(2))
    #expect(r.battery?.left == 55)
    #expect(r.airPods?.listeningMode == .seffaf)
}

@Test func reducerClearAirPodsDurumuSilerPiliTutar() {
    var r = DeviceStateReducer(startedAt: t0)
    r.updateAirPods(state(left: 90, right: 80, mode: .seffaf), at: at(1))
    r.clearAirPods()
    #expect(r.airPods == nil)
    #expect(r.battery?.left == 90)
}

@Test func reducerAirPodsBaglantiDurumunuDegistirmez() {
    var r = DeviceStateReducer(startedAt: t0)
    r.setConnection(.degil, at: at(1))
    r.updateAirPods(state(left: 90), at: at(2))
    #expect(r.state(at: at(3)) == .bagliDegil)
}
