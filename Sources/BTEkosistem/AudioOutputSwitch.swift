// CoreAudio cikis aygitlari: listeleme, Bluetooth kulaklik eslemesi, varsayilan cikisi ayarlama.
import CoreAudio
import Foundation

struct AudioOutput: Sendable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

enum AudioOutputSwitch {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ sel: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Listeleme

    /// En az bir cikis kanali olan tum aygitlar.
    static func outputs() -> [AudioOutput] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard outputChannels(id) > 0 else { return nil }
            return AudioOutput(id: id, uid: string(id, kAudioDevicePropertyDeviceUID),
                               name: string(id, kAudioObjectPropertyName), transport: transport(id))
        }
    }

    /// Varsayilan cikis aygiti (yoksa nil).
    static func defaultOutputID() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &dev) == noErr,
              dev != kAudioObjectUnknown else { return nil }
        return dev
    }

    // MARK: Esleme

    /// Ayrac ve harf farkini yok sayar: "84:AC:60:20:9D:3A" ~ "84-ac-60-20-9d-3a:output" -> "84ac60209d3a".
    static func normalizedAddress(_ text: String) -> String {
        let head = text.split(separator: ":", omittingEmptySubsequences: false)
        // Iki nokta ayracli adreste ":output" gibi sonek olabilir; hex olmayan sonekleri at.
        let hex = Set("0123456789abcdef")
        var digits = ""
        for part in head {
            let p = part.lowercased().filter { $0 != "-" && $0 != "_" }
            if p.allSatisfy({ hex.contains($0) }), !p.isEmpty, digits.count < 12 { digits += p } else if digits.count >= 12 { break }
        }
        return String(digits.prefix(12))
    }

    /// Once adres (UID icinde), yedek olarak ad eslemesi. Yalniz Bluetooth tasima turlu aygitlar.
    static func match(address: String, name: String, in list: [AudioOutput]) -> AudioOutput? {
        let target = normalizedAddress(address)
        let bt = list.filter(\.isBluetooth)
        if target.count == 12, let hit = bt.first(where: { normalizedAddress($0.uid) == target }) { return hit }
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !n.isEmpty else { return nil }
        return bt.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == n }
    }

    static func headphone(address: String, name: String) -> AudioOutput? {
        match(address: address, name: name, in: outputs())
    }

    /// Yerlesik hoparlor (kulaklik jakli yerlesik aygit da olabilir; ilk yerlesik cikis).
    static func builtInSpeaker() -> AudioOutput? {
        let list = outputs().filter(\.isBuiltIn)
        return list.first { $0.name.lowercased().contains("speaker") || $0.name.lowercased().contains("hoparl") } ?? list.first
    }

    // MARK: Ayarlama

    @discardableResult
    static func setDefault(_ output: AudioOutput) -> Bool {
        var dev = output.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a1 = address(kAudioHardwarePropertyDefaultOutputDevice)
        let ok = AudioObjectSetPropertyData(system, &a1, 0, nil, size, &dev) == noErr
        var a2 = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        _ = AudioObjectSetPropertyData(system, &a2, 0, nil, size, &dev)
        return ok
    }

    /// Aygit listede belirene kadar birkac kez dener (Bluetooth cikisi baglantidan sonra gecikmeli gelir).
    static func setDefaultWhenAvailable(address: String, name: String, attempts: Int = 8) async -> Bool {
        for i in 0..<attempts {
            if let out = headphone(address: address, name: name), setDefault(out) { return true }
            if i < attempts - 1 { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return false
    }

    // MARK: Ic

    private static func outputChannels(_ dev: AudioObjectID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transport(_ dev: AudioObjectID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &t)
        return t
    }

    private static func string(_ dev: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
        var addr = address(sel)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &cf) == noErr, let cf else { return "" }
        return cf.takeRetainedValue() as String
    }
}
