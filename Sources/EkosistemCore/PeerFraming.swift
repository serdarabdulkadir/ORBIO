import Foundation

public enum PeerFrameError: Error, Equatable, Sendable {
    case bosCerceve
    case cokBuyuk(Int)
}

/// Cerceve: 4 bayt big-endian uzunluk + yuk. En fazla 1 MiB.
public enum PeerFrame {
    public static let maxPayload = 1_048_576

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw PeerFrameError.bosCerceve }
        guard payload.count <= maxPayload else { throw PeerFrameError.cokBuyuk(payload.count) }
        var out = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

/// Parcali gelen baytlari birlestirip tam cerceveleri verir. Hata sonrasi tampon kullanilmamalidir.
public struct PeerFrameBuffer: Sendable {
    private var buffer = Data()
    public init() {}

    public var pendingByteCount: Int { buffer.count }

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let s = buffer.startIndex
            let len = (Int(buffer[s]) << 24) | (Int(buffer[s + 1]) << 16) | (Int(buffer[s + 2]) << 8) | Int(buffer[s + 3])
            if len == 0 { throw PeerFrameError.bosCerceve }
            if len > PeerFrame.maxPayload { throw PeerFrameError.cokBuyuk(len) }
            guard buffer.count >= 4 + len else { break }
            frames.append(Data(buffer[(s + 4)..<(s + 4 + len)]))
            buffer = Data(buffer[(s + 4 + len)...])
        }
        return frames
    }
}
