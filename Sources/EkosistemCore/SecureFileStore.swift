import Foundation

// Kucuk gizli verileri (kimlik anahtari, pin) Anahtar Zinciri'ne baglanmadan dizinde 0600 izinli dosyada saklar.
// Ad-hoc yeniden imzada Anahtar Zinciri erisimi kaybolurken Application Support dosyalari etkilenmez.

public struct SecureFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// `~/Library/Application Support/<ad>`
    public static func applicationSupport(_ name: String) -> SecureFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return SecureFileStore(directory: base.appendingPathComponent(name, isDirectory: true))
    }

    public enum ReadResult: Equatable, Sendable {
        case data(Data)
        case missing
        case failed
    }

    public func read(_ file: String) -> ReadResult {
        let url = directory.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let d = try? Data(contentsOf: url) else { return .failed }
        return .data(d)
    }

    @discardableResult
    public func write(_ data: Data, to file: String) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(file)
            let tmp = directory.appendingPathComponent(file + ".tmp")
            try? fm.removeItem(at: tmp)
            guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    public func delete(_ file: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }
}
