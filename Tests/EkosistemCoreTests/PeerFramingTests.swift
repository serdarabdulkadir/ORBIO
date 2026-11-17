import Testing
import Foundation
@testable import EkosistemCore

@Test func cerceveTuruVeUzunlukOnek() throws {
    let f = try PeerFrame.encode(Data([1, 2, 3]))
    #expect([UInt8](f) == [0, 0, 0, 3, 1, 2, 3])
    var b = PeerFrameBuffer()
    #expect(try b.append(f) == [Data([1, 2, 3])])
    #expect(b.pendingByteCount == 0)
}

@Test func parcaliVeBirlesikCerceveler() throws {
    let a = try PeerFrame.encode(Data("merhaba".utf8)), c = try PeerFrame.encode(Data("dunya".utf8))
    let all = a + c
    var b = PeerFrameBuffer()
    var got: [Data] = []
    for byte in all { got += try b.append(Data([byte])) }   // bayt bayt
    #expect(got == [Data("merhaba".utf8), Data("dunya".utf8)])
    var b2 = PeerFrameBuffer()
    #expect(try b2.append(all.prefix(6)).isEmpty)
    #expect(try b2.append(all.dropFirst(6)).count == 2)
}

@Test func bozukCerceveReddedilir() throws {
    var b = PeerFrameBuffer()
    #expect(throws: PeerFrameError.bosCerceve) { try b.append(Data([0, 0, 0, 0])) }
    var b2 = PeerFrameBuffer()
    #expect(throws: PeerFrameError.cokBuyuk(0x01000000)) { try b2.append(Data([1, 0, 0, 0])) }
    #expect(throws: PeerFrameError.bosCerceve) { try PeerFrame.encode(Data()) }
    #expect(throws: PeerFrameError.cokBuyuk(PeerFrame.maxPayload + 1)) {
        try PeerFrame.encode(Data(count: PeerFrame.maxPayload + 1))
    }
    var b3 = PeerFrameBuffer()   // kisa baslik: bekler, hata vermez
    #expect(try b3.append(Data([0, 0])).isEmpty)
    #expect(b3.pendingByteCount == 2)
}
