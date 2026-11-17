// QCY GATT yazma kuyrugu (saf mantik): tum yazma / okuma istekleri tek sirada, en az `minInterval` arayla gider.
// Ayni anahtarli bekleyen istek birlesir (son yazilan kazanir); kullanici yazmalari bekleyen arka plan okumalarinin onune gecer.
// Amac: A2DP akarken kulakligin BLE denetleyicisine art arda yazma yagdirmamak (cizirti riski).
import Foundation

public struct QcyWriteItem: Equatable, Sendable {
    public enum Target: String, Sendable { case command, keyMap, legacyEq, keyMapRead, batteryRead }

    public var target: Target
    public var bytes: [UInt8]
    /// Ayni anahtarli bekleyen istek yenisiyle degistirilir; nil = hic birlesmez (cok paketli EQ dizisi).
    public var key: String?
    /// Bu andan once gonderilmez (yazma sonrasi geri okuma gecikmesi).
    public var notBefore: Date

    /// Cok paketli / sirali komutlar: birlestirilemez.
    private static let sequenceOpcodes: Set<UInt8> = [0x20, 0x22, 0x46, 0x47]

    public init(target: Target, bytes: [UInt8], key: String?, notBefore: Date) {
        self.target = target; self.bytes = bytes; self.key = key; self.notBefore = notBefore
    }

    /// Hedefe ve paket icerigine gore anahtar uretir: okuma istegi `r:<opcode>`, yazma `w:<opcode>`.
    public static func make(target: Target, bytes: [UInt8], notBefore: Date) -> QcyWriteItem {
        let key: String?
        switch target {
        case .command:
            if bytes.count >= 5, bytes[0] == 0xFF, bytes[2] == 0xFE {
                key = "r:\(bytes[4])"
            } else if bytes.count >= 3, bytes[0] == 0xFF {
                key = sequenceOpcodes.contains(bytes[2]) ? nil : "w:\(bytes[2])"
            } else {
                key = nil
            }
        case .keyMap: key = "w:000d"
        case .legacyEq: key = "w:000b"
        case .keyMapRead: key = "r:000d"
        case .batteryRead: key = "r:0008"
        }
        return QcyWriteItem(target: target, bytes: bytes, key: key, notBefore: notBefore)
    }

    /// Okuma istekleri (sorgu paketi / ozellik okumasi) kullanici yazmasindan sonra gelir.
    public var isRead: Bool { key?.hasPrefix("r:") ?? false }
}

public struct QcyWriteQueue: Sendable {
    public enum Next: Equatable, Sendable {
        case write(QcyWriteItem)
        /// Siradaki istege kadar beklenecek sure (sn).
        case wait(TimeInterval)
        case empty
    }

    public let minInterval: TimeInterval
    public private(set) var pending: [QcyWriteItem] = []
    private var lastWrite: Date?

    public init(minInterval: TimeInterval = 0.2) { self.minInterval = minInterval }

    public var isEmpty: Bool { pending.isEmpty }

    /// Ayni anahtarli bekleyen istek varsa silinir, yenisi sona eklenir.
    public mutating func enqueue(_ item: QcyWriteItem) {
        if let key = item.key { pending.removeAll { $0.key == key } }
        pending.append(item)
    }

    public mutating func clear() { pending.removeAll() }

    /// Su an gonderilebilecek istek varsa onu verir (ve araligi baslatir); yoksa ne kadar beklenecegini soyler.
    public mutating func next(now: Date) -> Next {
        guard !pending.isEmpty else { return .empty }
        let gate = lastWrite.map { $0.addingTimeInterval(minInterval) } ?? .distantPast
        let readyAt: (QcyWriteItem) -> Date = { max($0.notBefore, gate) }
        let ready = pending.indices.filter { readyAt(pending[$0]) <= now }
        if let index = ready.first(where: { !pending[$0].isRead }) ?? ready.first {
            lastWrite = now
            return .write(pending.remove(at: index))
        }
        let soonest = pending.map(readyAt).min() ?? now
        return .wait(max(soonest.timeIntervalSince(now), 0.01))
    }
}
