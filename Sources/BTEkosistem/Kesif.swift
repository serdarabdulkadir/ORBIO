// Protokol kesfi: `--kesif` eslesmis sesi cihazlarin SDP (RFCOMM) kayitlarini ve BLE GATT servislerini dokar.
import Foundation
import CoreBluetooth
import IOBluetooth
import EkosistemCore


final class Kesif: NSObject, @unchecked Sendable, CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated(unsafe) static var instance: Kesif?
    private var central: CBCentralManager!
    private var found: [UUID: CBPeripheral] = [:]
    private let hedef = ["qcy", "melobuds"]

    nonisolated static func run() {
        // 1) Klasik: SDP kayitlari
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where d.deviceClassMajor == 0x04 {
            print("== SDP \(d.name ?? "?") \(d.addressString ?? "")  bagli=\(d.isConnected())")
            for case let r as IOBluetoothSDPServiceRecord in d.services ?? [] {
                var ch: BluetoothRFCOMMChannelID = 0
                let hasRF = r.getRFCOMMChannelID(&ch) == kIOReturnSuccess
                var uuids: [String] = []
                if let attr = r.getAttributeDataElement(0x0001), let arr = attr.getArrayValue() {
                    for case let e as IOBluetoothSDPDataElement in arr {
                        if let u = e.getUUIDValue() { uuids.append("\(u)") }
                    }
                }
                print("  servis \"\(r.getServiceName() ?? "-")\" rfcomm=\(hasRF ? "\(ch)" : "-") uuid=\(uuids)")
            }
        }
        // 2) BLE tarama + GATT
        let k = Kesif(); instance = k
        k.central = CBCentralManager(delegate: k, queue: .main)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        do {
            print("CB durum=\(c.state.rawValue)")
            if c.state == .poweredOn { c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        do {
            guard found[p.identifier] == nil else { return }
            found[p.identifier] = p
            let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "-"
            let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data)?.map { String(format: "%02X", $0) }.joined() ?? "-"
            let uuids = (ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
            print("BLE \(name) rssi=\(rssi) mfg=\(mfg) uuid=\(uuids)")
            if hedef.contains(where: { name.lowercased().contains($0) }) {
                print("  -> hedef, baglaniliyor")
                c.connect(p)
            }
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        do { p.delegate = self; p.discoverServices(nil) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        do { for s in p.services ?? [] { print("  servis \(s.uuid)"); p.discoverCharacteristics(nil, for: s) } }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        do {
            for c in s.characteristics ?? [] {
                print("    ozellik \(c.uuid) \(c.properties.rawValue)")
                if c.properties.contains(.read) { p.readValue(for: c) }
                if c.properties.contains(.notify) { p.setNotifyValue(true, for: c) }
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        do { print("    deger \(c.uuid) = \(c.value?.map { String(format: "%02X", $0) }.joined() ?? "-")") }
    }
}

// `--sorgu`: MeloBuds'a baglanir, GATT ozelliklerini dokar ve YALNIZCA okuma istekleri (FE <opcode>) gonderir.
@MainActor
final class Sorgu: NSObject, @unchecked Sendable, CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated(unsafe) static var instance: Sorgu?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var komut: CBCharacteristic?
    private var basladi = false
    private var bekleyenServis = 0
    private let opcodes: [UInt8] = [0x06, 0x09, 0x10, 0x14, 0x17, 0x1D, 0x22, 0x23, 0x24, 0x2A, 0x2C, 0x2F]
    private let ilgili: Set<String> = ["1001", "1002", "0007", "0008", "000B", "000D"]
    private var yanitlar: [UInt8: [UInt8]] = [:]

    static func run() {
        let s = Sorgu(); instance = s
        s.central = CBCentralManager(delegate: s, queue: .main)
    }

    private static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

    private func props(_ p: CBCharacteristicProperties) -> String {
        var a: [String] = []
        if p.contains(.read) { a.append("read") }
        if p.contains(.write) { a.append("write") }
        if p.contains(.writeWithoutResponse) { a.append("writeNoResp") }
        if p.contains(.notify) { a.append("notify") }
        if p.contains(.indicate) { a.append("indicate") }
        return "\(p.rawValue)[\(a.joined(separator: ","))]"
    }

    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        let st = c.state
        MainActor.assumeIsolated {
            print("CB durum=\(st.rawValue)")
            if st == .poweredOn { self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData ad: [String: Any], rssi: NSNumber) {
        nonisolated(unsafe) let p = peripheral
        let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            guard self.peripheral == nil, mfg.count >= 2, mfg[0] == 0x1C, mfg[1] == 0x52 else { return }
            print("QCY reklam bulundu rssi=\(rssi) mfg=\(Sorgu.hex(mfg))")
            self.peripheral = p
            self.central.stopScan()
            self.central.connect(p)
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect peripheral: CBPeripheral) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated { print("baglandi"); p.delegate = self; p.discoverServices(nil) }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { print("baglanti HATA \(String(describing: error))") }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated {
            self.bekleyenServis = p.services?.count ?? 0
            for s in p.services ?? [] { print("servis \(s.uuid)"); p.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let s = service
        MainActor.assumeIsolated {
            for c in s.characteristics ?? [] {
                let id = c.uuid.uuidString.uppercased()
                let sid = s.uuid.uuidString.uppercased()
                print("  ozellik \(sid)/\(id) props=\(self.props(c.properties))")
                if self.ilgili.contains(id) || c.properties.contains(.read) {
                    if c.properties.contains(.read) { p.readValue(for: c) }
                }
                if sid == "A001" && id == "1002" { p.setNotifyValue(true, for: c) }
                if sid == "A001" && id == "1001" { self.komut = c }
            }
            self.bekleyenServis -= 1
            if self.bekleyenServis == 0 { self.baslat(p) }
        }
    }

    private func baslat(_ p: CBPeripheral) {
        guard !basladi, let k = komut else { print("A001/1001 bulunamadi"); return }
        basladi = true
        nonisolated(unsafe) let pp = p
        nonisolated(unsafe) let kk = k
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let tur: CBCharacteristicWriteType = kk.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            for op in self.opcodes {
                let paket = QcyPacket.request(opcode: op)   // yalnizca FE istegi
                print(">> istek op=\(String(format: "%02X", op)) \(Sorgu.hex(paket))")
                pp.writeValue(Data(paket), for: kk, type: tur)
                try? await Task.sleep(for: .milliseconds(300))
            }
            try? await Task.sleep(for: .seconds(1.5))
            self.ozet()
        }
    }

    private func ozet() {
        print("---- OZET")
        for op in opcodes {
            if let prm = yanitlar[op] {
                print("op \(String(format: "%02X", op)) YANIT params=\(Sorgu.hex(prm))  \(Sorgu.yorum(op, prm))")
            } else {
                print("op \(String(format: "%02X", op)) YANIT YOK")
            }
        }
    }

    static func yorum(_ op: UInt8, _ p: [UInt8]) -> String {
        if op == 0x17, let m = QcyNoise.parseMode(p) { return "ses modu=\(m)" }
        return ""
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let c = characteristic
        let v = c.value.map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            let id = c.uuid.uuidString.uppercased()
            if id == "1002" {
                print("<< 1002 ham=\(Sorgu.hex(v))")
                for (op, prm) in QcyPacket.parse(v) {
                    print("   blok op=\(String(format: "%02X", op)) params=\(Sorgu.hex(prm))")
                    self.yanitlar[op] = prm
                }
            } else {
                print("  deger \(id) = \(v.isEmpty ? "-" : Sorgu.hex(v))")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { MainActor.assumeIsolated { print("yazma HATA \(error)") } }
    }
}

// `--tara` / `--dinle`: SALT OKUNUR. MeloBuds'a baglanir; tara 0x01..0x40 FE okuma isteklerini dener,
// dinle 120 sn boyunca tum bildirimleri zaman damgasiyla yazar ve 0008'i 5 sn'de bir okur.
@MainActor
final class Tara: NSObject, @unchecked Sendable, CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated(unsafe) static var instance: Tara?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var komut: CBCharacteristic?
    private var batarya: CBCharacteristic?
    private var basladi = false
    private var bekleyenServis = 0
    private var dinleModu = false
    private var yanitlar: [UInt8: [UInt8]] = [:]
    private var son: [String: [UInt8]] = [:]
    private var ozellikler: [(servis: String, id: String, c: CBCharacteristic)] = []
    private var okunanlar: [String: [UInt8]] = [:]
    private var t0 = Date()

    static func run(dinle: Bool) {
        let s = Tara(); instance = s
        s.dinleModu = dinle
        s.central = CBCentralManager(delegate: s, queue: .main)
    }

    private static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }
    private static func op(_ o: UInt8) -> String { String(format: "%02X", o) }

    private func ts() -> String {
        let t = Date().timeIntervalSince(t0)
        let m = Int(t) / 60
        return String(format: "%02d:%06.3f", m, t - Double(m * 60))
    }

    private func props(_ p: CBCharacteristicProperties) -> String {
        var a: [String] = []
        if p.contains(.read) { a.append("read") }
        if p.contains(.write) { a.append("write") }
        if p.contains(.writeWithoutResponse) { a.append("writeNoResp") }
        if p.contains(.notify) { a.append("notify") }
        if p.contains(.indicate) { a.append("indicate") }
        return "\(p.rawValue)[\(a.joined(separator: ","))]"
    }

    private func bitir() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            exit(0)
        }
    }

    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        let st = c.state
        MainActor.assumeIsolated {
            print("CB durum=\(st.rawValue)")
            if st == .poweredOn { self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData ad: [String: Any], rssi: NSNumber) {
        nonisolated(unsafe) let p = peripheral
        let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            guard self.peripheral == nil, mfg.count >= 2, mfg[0] == 0x1C, mfg[1] == 0x52 else { return }
            print("QCY reklam bulundu rssi=\(rssi) mfg=\(Tara.hex(mfg))")
            self.peripheral = p
            self.central.stopScan()
            self.central.connect(p)
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect peripheral: CBPeripheral) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated { self.t0 = Date(); print("baglandi"); p.delegate = self; p.discoverServices(nil) }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { print("baglanti HATA \(String(describing: error))"); exit(1) }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { print("[\(self.ts())] baglanti koptu \(error.map { "\($0)" } ?? "")") }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated {
            self.bekleyenServis = p.services?.count ?? 0
            for s in p.services ?? [] { print("servis \(s.uuid)"); p.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let s = service
        MainActor.assumeIsolated {
            let sid = s.uuid.uuidString.uppercased()
            for c in s.characteristics ?? [] {
                let id = c.uuid.uuidString.uppercased()
                print("  ozellik \(sid)/\(id) props=\(self.props(c.properties))")
                self.ozellikler.append((sid, id, c))
                if c.properties.contains(.read) { p.readValue(for: c) }
                let bildir = (sid == "A001" && id == "1002") || id == "0008" || (sid == "7033" && (id == "1002" || id == "2002"))
                if bildir, c.properties.contains(.notify) || c.properties.contains(.indicate) { p.setNotifyValue(true, for: c) }
                if sid == "A001" && id == "1001" { self.komut = c }
                if id == "0008" { self.batarya = c }
            }
            self.bekleyenServis -= 1
            if self.bekleyenServis == 0 { self.baslat(p) }
        }
    }

    private func baslat(_ p: CBPeripheral) {
        guard !basladi else { return }
        basladi = true
        nonisolated(unsafe) let pp = p
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if self.dinleModu { await self.dinle(pp) } else { await self.tara(pp) }
        }
    }

    private func tara(_ p: CBPeripheral) async {
        guard let kk = komut else { print("A001/1001 bulunamadi"); bitir(); return }
        nonisolated(unsafe) let k = kk
        let tur: CBCharacteristicWriteType = k.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for op in UInt8(0x01)...UInt8(0x40) {
            let paket = QcyPacket.request(opcode: op)   // yalnizca FE istegi
            p.writeValue(Data(paket), for: k, type: tur)
            try? await Task.sleep(for: .milliseconds(150))
        }
        try? await Task.sleep(for: .seconds(2))
        print("---- YANIT VEREN OPCODE TABLOSU")
        for op in yanitlar.keys.sorted() {
            print("op \(Tara.op(op))  params=\(Tara.hex(yanitlar[op]!))")
        }
        print("yanit veren: \(yanitlar.count) / 64")
        print("---- 7033 SERVISI OZELLIKLERI")
        let l = ozellikler.filter { $0.servis == "7033" }
        if l.isEmpty { print("7033 servisi YOK") }
        for o in l {
            let v = okunanlar["7033/\(o.id)"].map { Tara.hex($0) } ?? "-"
            print("7033/\(o.id) props=\(props(o.c.properties)) okunan=\(v)")
        }
        print("---- OKUNAN TUM DEGERLER")
        for k in okunanlar.keys.sorted() { print("\(k) = \(Tara.hex(okunanlar[k]!))") }
        bitir()
    }

    private func dinle(_ p: CBPeripheral) async {
        print("---- DINLE basladi (120 sn). Kutuyu ac/kapat, kulakliklari koy/cikar.")
        let bitis = Date().addingTimeInterval(120)
        while Date() < bitis {
            if let b = batarya, b.properties.contains(.read) { p.readValue(for: b) }
            try? await Task.sleep(for: .seconds(5))
        }
        print("[\(ts())] ---- DINLE bitti")
        bitir()
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let c = characteristic
        let v = c.value.map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            let id = c.uuid.uuidString.uppercased()
            let sid = c.service?.uuid.uuidString.uppercased() ?? "?"
            let key = "\(sid)/\(id)"
            let degisti = self.son[key] != v
            self.son[key] = v
            self.okunanlar[key] = v
            if sid == "A001" && id == "1002" {
                if self.dinleModu { print("[\(self.ts())] \(key) ham=\(Tara.hex(v))") }
                for (op, prm) in QcyPacket.parse(v) {
                    self.yanitlar[op] = prm
                    if self.dinleModu { print("[\(self.ts())]   blok op=\(Tara.op(op)) params=\(Tara.hex(prm))") }
                }
            } else if self.dinleModu {
                print("[\(self.ts())] \(key) = \(Tara.hex(v)) \(degisti ? "(DEGISTI)" : "(ayni)")")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { MainActor.assumeIsolated { print("yazma HATA \(error)") } }
    }
}

// `--seffaf <deger>` / `--seffaf-dene`: seffaf mod seviyesini dener (0x17 `03 01 <deger>`).
// Once mevcut 0x17 parametreleri okunur; orijinal bilinmiyorsa HIC yazma yapilmaz. Sonunda orijinal aynen geri yazilir.
@MainActor
final class Seffaf: NSObject, @unchecked Sendable, CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated(unsafe) static var instance: Seffaf?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var komut: CBCharacteristic?
    private var basladi = false
    private var bekleyenServis = 0
    private var degerler: [UInt8] = []
    private var son17: [UInt8]?
    private var t0 = Date()

    static func run(degerler: [UInt8]) {
        let s = Seffaf(); instance = s
        s.degerler = degerler
        s.central = CBCentralManager(delegate: s, queue: .main)
    }

    private static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

    private func log(_ m: String) {
        let t = Date().timeIntervalSince(t0)
        let dk = Int(t) / 60
        print(String(format: "[%02d:%06.3f] ", dk, t - Double(dk * 60)) + m)
    }

    private func bitir(_ kod: Int32) {
        if let p = peripheral { central.cancelPeripheralConnection(p); log("baglanti kapatiliyor") }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            exit(kod)
        }
    }

    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        let st = c.state
        MainActor.assumeIsolated {
            print("CB durum=\(st.rawValue)")
            if st == .poweredOn { self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData ad: [String: Any], rssi: NSNumber) {
        nonisolated(unsafe) let p = peripheral
        let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            guard self.peripheral == nil, mfg.count >= 2, mfg[0] == 0x1C, mfg[1] == 0x52 else { return }
            print("QCY reklam bulundu rssi=\(rssi) mfg=\(Seffaf.hex(mfg))")
            self.peripheral = p
            self.central.stopScan()
            self.central.connect(p)
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect peripheral: CBPeripheral) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated { self.t0 = Date(); self.log("baglandi"); p.delegate = self; p.discoverServices(nil) }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { print("baglanti HATA \(String(describing: error))"); exit(1) }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { self.log("baglanti koptu \(error.map { "\($0)" } ?? "")") }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated {
            self.bekleyenServis = p.services?.count ?? 0
            for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let s = service
        MainActor.assumeIsolated {
            let sid = s.uuid.uuidString.uppercased()
            for c in s.characteristics ?? [] {
                let id = c.uuid.uuidString.uppercased()
                if sid == "A001" && id == "1002" { p.setNotifyValue(true, for: c) }
                if sid == "A001" && id == "1001" { self.komut = c }
            }
            self.bekleyenServis -= 1
            if self.bekleyenServis == 0 { self.baslat(p) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let c = characteristic
        let v = c.value.map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            guard c.uuid.uuidString.uppercased() == "1002" else { return }
            self.log("<< 1002 ham=\(Seffaf.hex(v))")
            for (op, prm) in QcyPacket.parse(v) where op == QcyNoise.opcode { self.son17 = prm }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { MainActor.assumeIsolated { self.log("yazma HATA \(error)") } }
    }

    private func baslat(_ p: CBPeripheral) {
        guard !basladi else { return }
        basladi = true
        nonisolated(unsafe) let pp = p
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            await self.akis(pp)
        }
    }

    private func yaz(_ p: CBPeripheral, _ k: CBCharacteristic, _ paket: [UInt8], _ etiket: String) {
        nonisolated(unsafe) let kk = k
        let tur: CBCharacteristicWriteType = kk.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        log(">> \(etiket) \(Seffaf.hex(paket))")
        p.writeValue(Data(paket), for: kk, type: tur)
    }

    /// 0x17 okuma istegi gonderir, `bekle` ms sonra son gelen parametreleri dondurur (yanit yoksa nil).
    private func oku17(_ p: CBPeripheral, _ k: CBCharacteristic, bekle: Int = 300) async -> [UInt8]? {
        son17 = nil
        yaz(p, k, QcyPacket.request(opcode: QcyNoise.opcode), "oku 0x17")
        try? await Task.sleep(for: .milliseconds(bekle))
        return son17
    }

    private func akis(_ p: CBPeripheral) async {
        guard let k = komut else { log("A001/1001 bulunamadi"); bitir(1); return }
        // (1) mevcut mod
        var orijinal = await oku17(p, k, bekle: 600)
        if orijinal == nil { orijinal = await oku17(p, k, bekle: 1000) }
        guard let orij = orijinal, !orij.isEmpty else {
            log("HATA: mevcut 0x17 okunamadi; guvenlik icin HICBIR sey yazilmadi")
            bitir(1); return
        }
        log("ORIJINAL 0x17 params=\(Seffaf.hex(orij))")

        // (3) deneme(ler)
        var tablo: [(UInt8, [UInt8]?, [UInt8]?)] = []
        for d in degerler {
            yaz(p, k, QcyPacket.pack(opcode: QcyNoise.opcode, [0x03, 0x01, d]), "seffaf seviye=\(String(format: "%02X", d))")
            try? await Task.sleep(for: .milliseconds(300))
            let yanit = son17   // yazma sonrasi cihazin kendiliginden gonderdigi bildirim (varsa)
            let geri = await oku17(p, k)
            log("seviye \(String(format: "%02X", d)): yazma-sonrasi bildirim=\(yanit.map { Seffaf.hex($0) } ?? "-") okuma=\(geri.map { Seffaf.hex($0) } ?? "YOK")")
            tablo.append((d, yanit, geri))
            log("8 sn bekleniyor (kulaklikta dinleyin)")
            try? await Task.sleep(for: .seconds(8))
        }

        // (4) orijinali geri yaz
        yaz(p, k, QcyPacket.pack(opcode: QcyNoise.opcode, orij), "ORIJINALE DON")
        try? await Task.sleep(for: .milliseconds(300))
        let geri = await oku17(p, k, bekle: 600)
        let tamam = geri == orij
        log("geri okuma=\(geri.map { Seffaf.hex($0) } ?? "YOK") -> \(tamam ? "ORIJINALE DONDU" : "UYARI: orijinalle ESLESMIYOR")")

        print("---- TABLO (orijinal=\(Seffaf.hex(orij)))")
        for (d, y, g) in tablo {
            let istek: [UInt8] = [0x03, 0x01, d]
            let sonuc: String
            if let g, g == istek { sonuc = "KABUL (deger aynen yansidi)" }
            else if let g, g == orij { sonuc = "REDDEDILDI/DEGISMEDI" }
            else if g != nil { sonuc = "FARKLI DEGER" }
            else { sonuc = "YANIT YOK" }
            print("seviye \(String(format: "%02X", d)) bildirim=\(y.map { Seffaf.hex($0) } ?? "-") okuma=\(g.map { Seffaf.hex($0) } ?? "-")  => \(sonuc)")
        }
        bitir(tamam ? 0 : 2)
    }
}
