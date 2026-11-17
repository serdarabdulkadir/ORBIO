import Testing
import Foundation
@testable import EkosistemCore

@Suite("QCY yazma kuyrugu")
struct QcyWriteQueueTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    private func read(_ op: UInt8, at t: Date) -> QcyWriteItem {
        .make(target: .command, bytes: QcyPacket.request(opcode: op), notBefore: t)
    }

    @Test func anahtarlar() {
        #expect(read(0x17, at: t0).key == "r:23")
        #expect(QcyWriteItem.make(target: .command, bytes: QcyNoise.setMode(.kapali)!, notBefore: t0).key == "w:23")
        #expect(QcyWriteItem.make(target: .keyMap, bytes: [UInt8](repeating: 0, count: 20), notBefore: t0).key == "w:000d")
        // Cok paketli EQ dizisi birlesmez.
        #expect(QcyWriteItem.make(target: .command, bytes: [0xFF, 0x03, 0x22, 0x01, 0x00], notBefore: t0).key == nil)
        #expect(read(0x17, at: t0).isRead)
        #expect(!QcyWriteItem.make(target: .command, bytes: QcyNoise.setMode(.kapali)!, notBefore: t0).isRead)
    }

    @Test func ilkYazmaHemenSonrakiAraliktaBekler() {
        var q = QcyWriteQueue(minInterval: 0.2)
        q.enqueue(read(0x17, at: t0)); q.enqueue(read(0x2C, at: t0))
        guard case .write = q.next(now: t0) else { Issue.record("ilk yazma hemen gitmeli"); return }
        guard case .wait(let w) = q.next(now: t0.addingTimeInterval(0.05)) else { Issue.record("bekle"); return }
        #expect(abs(w - 0.15) < 0.001)
        guard case .write = q.next(now: t0.addingTimeInterval(0.2)) else { Issue.record("aralik doldu"); return }
        #expect(q.next(now: t0.addingTimeInterval(1)) == .empty)
    }

    @Test func ayniOpcodeOkumasiBirlesir() {
        var q = QcyWriteQueue()
        for _ in 0..<5 { q.enqueue(read(0x17, at: t0)) }
        #expect(q.pending.count == 1)
    }

    @Test func sonYazilanKazanir() {
        var q = QcyWriteQueue()
        q.enqueue(.make(target: .command, bytes: QcyNoise.setMode(.kapali)!, notBefore: t0))
        q.enqueue(.make(target: .command, bytes: QcyNoise.setMode(.seffaf)!, notBefore: t0))
        #expect(q.pending.count == 1)
        #expect(q.pending[0].bytes == QcyNoise.setMode(.seffaf)!)
    }

    @Test func kullaniciYazmasiBekleyenOkumanOnundeGider() {
        var q = QcyWriteQueue()
        q.enqueue(read(0x17, at: t0)); q.enqueue(read(0x2C, at: t0))
        let set = QcyWriteItem.make(target: .command, bytes: QcyGameMode.packet(enabled: true), notBefore: t0)
        q.enqueue(set)
        #expect(q.next(now: t0) == .write(set))
    }

    @Test func geriOkumaGecikmesiOncedenGelenOkumayiBeklemez() {
        var q = QcyWriteQueue(minInterval: 0.2)
        let delayed = read(0x17, at: t0.addingTimeInterval(0.35))
        q.enqueue(delayed)
        q.enqueue(read(0x2C, at: t0))
        // Hazir olan (0x2C) once; geciken sonra.
        guard case .write(let first) = q.next(now: t0) else { Issue.record("yazma"); return }
        #expect(first.key == "r:44")
        guard case .wait(let w) = q.next(now: t0.addingTimeInterval(0.2)) else { Issue.record("bekle"); return }
        #expect(abs(w - 0.15) < 0.001)
        #expect(q.next(now: t0.addingTimeInterval(0.35)) == .write(delayed))
    }

    @Test func temizlemeBekleyenleriAtar() {
        var q = QcyWriteQueue()
        q.enqueue(read(0x17, at: t0))
        q.clear()
        #expect(q.next(now: t0) == .empty)
    }

    @Test func yirmiIstekEnAzAralikla() {
        var q = QcyWriteQueue(minInterval: 0.2)
        for op in 1...20 { q.enqueue(read(UInt8(op), at: t0)) }
        var now = t0, times: [Date] = []
        while true {
            switch q.next(now: now) {
            case .write: times.append(now)
            case .wait(let w): now = now.addingTimeInterval(w)
            case .empty: for (a, b) in zip(times, times.dropFirst()) { #expect(b.timeIntervalSince(a) >= 0.199) }
                #expect(times.count == 20)
                return
            }
        }
    }
}

@Suite("Tarama zamanlayicisi")
struct ScanSchedulerTests {
    let t0 = Date(timeIntervalSince1970: 5_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func profilSecimi() {
        #expect(ScanProfile.resolve(qcyNeedsAdvert: true, qcyReadyWithoutGattBattery: false, appleKnown: false) == .active)
        #expect(ScanProfile.resolve(qcyNeedsAdvert: false, qcyReadyWithoutGattBattery: false, appleKnown: true) == .active)
        #expect(ScanProfile.resolve(qcyNeedsAdvert: false, qcyReadyWithoutGattBattery: true, appleKnown: false) == .sparse)
        #expect(ScanProfile.resolve(qcyNeedsAdvert: false, qcyReadyWithoutGattBattery: false, appleKnown: false) == .off)
    }

    @Test func etkinPencere4AcikYirmiKapali() {
        var s = ScanScheduler()
        #expect(s.tick(now: at(0), profile: .active) == .start(allowDuplicates: true))
        #expect(s.tick(now: at(3), profile: .active) == .none)
        #expect(s.tick(now: at(4), profile: .active) == .stop)
        #expect(s.tick(now: at(23), profile: .active) == .none)
        #expect(s.tick(now: at(24), profile: .active) == .start(allowDuplicates: true))
    }

    @Test func kapaliAnindaDurdurur() {
        var s = ScanScheduler()
        _ = s.tick(now: at(0), profile: .active)
        #expect(s.tick(now: at(1), profile: .off) == .stop)
        #expect(s.tick(now: at(2), profile: .off) == .none)
        #expect(!s.isScanning)
    }

    @Test func seyrekPencereTekrarsizVeUzunKapali() {
        var s = ScanScheduler()
        #expect(s.tick(now: at(0), profile: .sparse) == .start(allowDuplicates: false))
        #expect(s.tick(now: at(2), profile: .sparse) == .stop)
        #expect(s.tick(now: at(61), profile: .sparse) == .none)
        #expect(s.tick(now: at(62), profile: .sparse) == .start(allowDuplicates: false))
    }

    @Test func kopunceTalepGelirseHemenAcilir() {
        var s = ScanScheduler()
        #expect(s.tick(now: at(0), profile: .off) == .none)
        #expect(s.tick(now: at(5), profile: .active) == .start(allowDuplicates: true))
    }

    @Test func seyrektenEtkineGecisKapaliSureyiKisaltir() {
        var s = ScanScheduler()
        _ = s.tick(now: at(0), profile: .sparse)
        _ = s.tick(now: at(2), profile: .sparse)      // 60 sn kapali basladi
        #expect(s.tick(now: at(30), profile: .active) == .start(allowDuplicates: true)) // 28 sn >= 20 sn: pencere
    }

    @Test func etkindeToplamYuk() {
        var s = ScanScheduler()
        var on = 0.0
        var scanning = false
        for sec in 0..<240 {
            switch s.tick(now: at(Double(sec)), profile: .active) {
            case .start: scanning = true
            case .stop: scanning = false
            case .none: break
            }
            if scanning { on += 1 }
        }
        #expect(on / 240 < 0.2) // ~%17: onceki %100'e karsi
    }

    @Test func sifirlamaBosta() {
        var s = ScanScheduler()
        _ = s.tick(now: at(0), profile: .active)
        s.reset()
        #expect(!s.isScanning)
        #expect(s.tick(now: at(1), profile: .active) == .start(allowDuplicates: true))
    }
}

@Suite("QCY geri cekilme")
struct QcyReconnectBackoffTests {
    let t0 = Date(timeIntervalSince1970: 9_000)

    @Test func artarVeSabitlenir() {
        var b = QcyReconnectBackoff()
        let got = (0..<7).map { _ in b.failed(now: t0, readySince: nil) }
        #expect(got == [5, 15, 45, 180, 180, 180, 180])
    }

    @Test func kisaOmurluBaglantiSayaciSifirlamaz() {
        var b = QcyReconnectBackoff()
        _ = b.failed(now: t0, readySince: nil)
        _ = b.failed(now: t0, readySince: nil)
        // 5 sn hazir kaldi, koptu: sayac devam eder.
        #expect(b.failed(now: t0.addingTimeInterval(100), readySince: t0.addingTimeInterval(95)) == 45)
    }

    @Test func kararliBaglantiSifirlar() {
        var b = QcyReconnectBackoff()
        for _ in 0..<4 { _ = b.failed(now: t0, readySince: nil) }
        #expect(b.failed(now: t0.addingTimeInterval(100), readySince: t0.addingTimeInterval(40)) == 5)
    }

    @Test func jitterVeResetFonksiyonu() {
        var b = QcyReconnectBackoff()
        #expect(abs(b.failed(now: t0, readySince: nil, jitter: 0.2) - 6) < 0.0001)
        b.reset()
        #expect(b.failures == 0)
    }
}

@Suite("QCY iyimser izleyici")
struct QcyOptimisticTrackerTests {
    let t0 = Date(timeIntervalSince1970: 20_000)

    @Test func cihazOnaylarsaKayitSilinir() {
        var t = QcyOptimisticTracker()
        t.begin(.gameMode(true), now: t0)
        let shown = t.reconcile(device: QcyDeviceState(gameMode: true), now: t0.addingTimeInterval(0.5))
        #expect(shown.gameMode == true)
        #expect(t.isEmpty)
    }

    @Test func eskiBildirimIyimserDegeriGeriCevirmez() {
        var t = QcyOptimisticTracker()
        t.begin(.gameMode(true), now: t0)
        let shown = t.reconcile(device: QcyDeviceState(gameMode: false), now: t0.addingTimeInterval(0.5))
        #expect(shown.gameMode == true)
        #expect(t.pendingCount == 1)
    }

    @Test func zamanAsimindaGeriAlinir() {
        var t = QcyOptimisticTracker()
        t.begin(.gameMode(true), now: t0)
        #expect(t.expire(now: t0.addingTimeInterval(3)).isEmpty)
        let dead = t.expire(now: t0.addingTimeInterval(4.1))
        #expect(dead == [.gameMode(true)])
        // Zamani dolan komut artik uygulanmaz: cihazin gercek durumu gorunur.
        #expect(t.reconcile(device: QcyDeviceState(gameMode: false), now: t0.addingTimeInterval(5)).gameMode == false)
    }

    @Test func ayniOpcodeSonYazilanKazanir() {
        var t = QcyOptimisticTracker()
        t.begin(.mode(.kapali), now: t0)
        t.begin(.mode(.seffaf), now: t0.addingTimeInterval(1))
        #expect(t.pendingCount == 1)
        let shown = t.reconcile(device: QcyDeviceState(mode: .kapali), now: t0.addingTimeInterval(1.5))
        #expect(shown.mode == .seffaf)
    }

    @Test func zamanAsimiSonrasiGelenBildirimBekleyeniUygulamaz() {
        var t = QcyOptimisticTracker()
        t.begin(.earDetection(true), now: t0)
        let shown = t.reconcile(device: QcyDeviceState(earDetection: false), now: t0.addingTimeInterval(9))
        #expect(shown.earDetection == false)
    }

    @Test func kanalKopunca() {
        var t = QcyOptimisticTracker()
        t.begin(.gameMode(true), now: t0)
        t.removeAll()
        #expect(t.isEmpty)
    }
}

@Suite("QCY pil ozelligi 0008")
struct QcyBatteryCharacteristicTests {
    @Test func uzunlukVeDegerler() {
        let r = QcyBatteryCharacteristic.parse([0x64, 0x80 | 40, 0], at: Date(timeIntervalSince1970: 1))
        #expect(r?.left == 100)
        #expect(r?.right == 40)
        #expect(r?.rightCharging == true)
        #expect(r?.caseLevel == nil)
        #expect(QcyBatteryCharacteristic.parse([1, 2], at: Date()) == nil)
        #expect(QcyBatteryCharacteristic.parse([0, 0, 0], at: Date()) == nil)
    }

    @Test func yapayReklamAyniCozucudenGecer() {
        let raw = QcyBatteryCharacteristic.syntheticAdvertisement([90, 80, 70], controlAddress: "00:11:22:33:44:55")
        let ad = raw.flatMap { QcyAdvertisement.parse(manufacturerData: $0) }
        #expect(ad?.left == 90)
        #expect(ad?.caseLevel == 70)
        #expect(ad?.controlAddress == "00:11:22:33:44:55")
        #expect(QcyBatteryCharacteristic.syntheticAdvertisement([1, 2, 3], controlAddress: "bozuk") == nil)
    }
}
