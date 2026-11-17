import Testing
import Foundation
@testable import EkosistemCore

private func tempStore() -> SecureFileStore {
    SecureFileStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("btrack-test-\(UUID().uuidString)", isDirectory: true))
}

@Test func dosyaYazOkuSilVe0600Izin() throws {
    let s = tempStore()
    defer { try? FileManager.default.removeItem(at: s.directory) }
    #expect(s.read("a") == .missing)
    #expect(s.write(Data([1, 2, 3]), to: "a"))
    #expect(s.read("a") == .data(Data([1, 2, 3])))
    #expect(s.write(Data([9]), to: "a"))   // uzerine yazma
    #expect(s.read("a") == .data(Data([9])))
    let attrs = try FileManager.default.attributesOfItem(atPath: s.directory.appendingPathComponent("a").path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let dir = try FileManager.default.attributesOfItem(atPath: s.directory.path)
    #expect((dir[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    s.delete("a")
    #expect(s.read("a") == .missing)
}
