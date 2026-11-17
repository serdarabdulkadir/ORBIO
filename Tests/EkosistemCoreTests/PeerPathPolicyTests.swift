import Testing
import Foundation
@testable import EkosistemCore

@Suite("Telefon yolu secimi")
struct PeerPathPolicyTests {
    let t0 = Date(timeIntervalSince1970: 40_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func wifiBeklemesiSonrasiBluetooth() {
        var p = PeerPathPolicy(now: t0)
        #expect(p.evaluate(now: at(5), wifiActive: false, bluetoothBusy: false, canTry: true) == .none)
        #expect(p.evaluate(now: at(10), wifiActive: false, bluetoothBusy: false, canTry: true) == .tryBluetooth)
    }

    @Test func adayYoksaDenenmez() {
        var p = PeerPathPolicy(now: t0)
        #expect(p.evaluate(now: at(60), wifiActive: false, bluetoothBusy: false, canTry: false) == .none)
    }

    @Test func wifiVarkenBluetoothDenenmezAcikSaOlurKapanir() {
        var p = PeerPathPolicy(now: t0)
        #expect(p.evaluate(now: at(30), wifiActive: true, bluetoothBusy: false, canTry: true) == .none)
        #expect(p.evaluate(now: at(31), wifiActive: true, bluetoothBusy: true, canTry: true) == .dropBluetooth)
    }

    @Test func wifiKopunca10SnSonraBluetooth() {
        var p = PeerPathPolicy(now: t0)
        _ = p.evaluate(now: at(100), wifiActive: true, bluetoothBusy: false, canTry: true)
        #expect(p.evaluate(now: at(101), wifiActive: false, bluetoothBusy: false, canTry: true) == .none)
        #expect(p.evaluate(now: at(105), wifiActive: false, bluetoothBusy: false, canTry: true) == .none)
        #expect(p.evaluate(now: at(111), wifiActive: false, bluetoothBusy: false, canTry: true) == .tryBluetooth)
    }

    @Test func mesgulkenYenidenDenenmez() {
        var p = PeerPathPolicy(now: t0)
        #expect(p.evaluate(now: at(50), wifiActive: false, bluetoothBusy: true, canTry: true) == .none)
    }

    @Test func basarisizlikUstelGeriCekilir() {
        var p = PeerPathPolicy(now: t0)
        let d = (0..<6).map { _ in p.bluetoothEnded(now: at(20), establishedAt: nil) }
        #expect(d == [15, 45, 120, 300, 300, 300])
        #expect(p.evaluate(now: at(100), wifiActive: false, bluetoothBusy: false, canTry: true) == .none)
        #expect(p.evaluate(now: at(330), wifiActive: false, bluetoothBusy: false, canTry: true) == .tryBluetooth)
    }

    @Test func kararliOturumSayaciSifirlar() {
        var p = PeerPathPolicy(now: t0)
        _ = p.bluetoothEnded(now: at(0), establishedAt: nil)
        _ = p.bluetoothEnded(now: at(0), establishedAt: nil)
        #expect(p.bluetoothEnded(now: at(200), establishedAt: at(100)) == 15)
    }

    @Test func wifiGelinceSayacSifirlanir() {
        var p = PeerPathPolicy(now: t0)
        _ = p.bluetoothEnded(now: at(0), establishedAt: nil)
        _ = p.evaluate(now: at(5), wifiActive: true, bluetoothBusy: false, canTry: true)
        #expect(p.failures == 0)
    }

    @Test func dosyaAktarimiYalnizWifi() {
        #expect(PeerPath.wifi.allowsFileTransfer)
        #expect(!PeerPath.bluetooth.allowsFileTransfer)
    }
}
