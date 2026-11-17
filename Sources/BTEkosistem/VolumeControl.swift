// Mac cikis sesi: CoreAudio varsayilan cikis aygitinin ses ozelligi + dinleyiciler, ve kaydirici karosu.
import AppKit
import CoreAudio
import Observation
import SwiftUI

@MainActor
@Observable
final class SystemVolume {
    /// Varsayilan cikis aygiti ses ayarini destekliyor mu (desteklemiyorsa karo gizlenir).
    private(set) var isSupported = false
    private(set) var level: Double = 0
    private(set) var muted = false
    /// Seviye ya da sessiz degisince (CoreAudio okumasindan sonra) cagrilir.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var lastNotified: (Double, Bool)?
    private(set) var outputSymbol = "speaker.wave.2.fill"
    private(set) var outputName = ""
    /// Varsayilan cikis su an eslesen kulaklik mi.
    private(set) var headphoneActive = false
    /// Eslesen kulaklik Mac'in cikis listesinde var mi (bagliysa).
    private(set) var headphoneAvailable = false
    /// Panelin gosterdigi kulaklik (adres + ad); eslemede kullanilir.
    @ObservationIgnored private var headphone: (address: String, name: String)?

    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var started = false
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var listenedDevice = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var listenedAddresses: [AudioObjectPropertyAddress] = []
    @ObservationIgnored private var defaultListener: AudioObjectPropertyListenerBlock?

    // 'vmvc' = kAudioHardwareServiceDeviceProperty_VirtualMainVolume (kullanimdan kalkan sabit yerine)
    private static let virtualMain = AudioObjectPropertySelector(0x766D_7663)

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !started else { return }
        started = true
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.reload() }
        }
        defaultListener = block
        var addr = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        // Aygit listesi degisince (kulaklik cikisi belirince) durumu yenile.
        var devices = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main, block)
        reload()
    }

    /// Eslenecek kulakligi bildirir; cikis durumunu yeniler.
    func setHeadphone(address: String?, name: String) {
        headphone = address.map { ($0, name) }
        reload()
    }

    /// Cikisi doner: kulaklik aktifse Mac hoparloru, degilse kulaklik.
    func toggleOutput() {
        guard let hp = headphone else { return }
        let list = AudioOutputSwitch.outputs()
        let target = headphoneActive ? AudioOutputSwitch.builtInSpeaker()
                                     : AudioOutputSwitch.match(address: hp.address, name: hp.name, in: list)
        guard let target else { return }
        AudioOutputSwitch.setDefault(target)
        reload()
    }

    /// Kaydirici degeri (0...1) cihaza yazilir; ekranda anlik yansir.
    func set(_ value: Double) {
        let v = Float32(min(max(value, 0), 1))
        level = Double(v)
        guard deviceID != kAudioObjectUnknown else { return }
        for var addr in volumeAddresses(deviceID) where isSettable(deviceID, &addr) {
            var val = v
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &val)
        }
    }

    /// Sessiz acik/kapali; cihaz desteklemiyorsa yok sayilir.
    func setMuted(_ value: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var addr = Self.muteAddress
        guard AudioObjectHasProperty(deviceID, &addr), isSettable(deviceID, &addr) else { return }
        var v: UInt32 = value ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        muted = value
    }

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private func readMuted(_ dev: AudioObjectID) -> Bool {
        var addr = Self.muteAddress
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr && v != 0
    }

    // MARK: Ic

    private func reload() {
        var addr = Self.defaultOutputAddress
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        guard st == noErr, dev != kAudioObjectUnknown else { clear(); return }
        if let hp = headphone {
            let match = AudioOutputSwitch.match(address: hp.address, name: hp.name, in: AudioOutputSwitch.outputs())
            headphoneAvailable = match != nil
            headphoneActive = match?.id == dev
        } else {
            headphoneAvailable = false
            headphoneActive = false
        }
        if dev != deviceID {
            detachVolumeListener()
            deviceID = dev
            outputName = Self.name(of: dev)
            outputSymbol = Self.symbol(of: dev, name: outputName)
            attachVolumeListener(dev)
        }
        guard let value = readVolume(dev) else { isSupported = false; return }
        isSupported = true
        level = Double(value)
        muted = readMuted(dev)
        if lastNotified?.0 != level || lastNotified?.1 != muted {
            lastNotified = (level, muted)
            onChange?()
        }
    }

    private func clear() {
        detachVolumeListener()
        deviceID = AudioObjectID(kAudioObjectUnknown)
        isSupported = false
        headphoneActive = false
    }

    private func volumeAddresses(_ dev: AudioObjectID) -> [AudioObjectPropertyAddress] {
        func a(_ sel: AudioObjectPropertySelector, _ el: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: el)
        }
        let candidates = [a(Self.virtualMain, kAudioObjectPropertyElementMain),
                          a(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)]
        for var c in candidates where AudioObjectHasProperty(dev, &c) { return [c] }
        // Ana eleman yoksa sol/sag kanallar.
        return [a(kAudioDevicePropertyVolumeScalar, 1), a(kAudioDevicePropertyVolumeScalar, 2)].filter {
            var c = $0
            return AudioObjectHasProperty(dev, &c)
        }
    }

    private func isSettable(_ dev: AudioObjectID, _ addr: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr && settable.boolValue
    }

    private func readVolume(_ dev: AudioObjectID) -> Float32? {
        var values: [Float32] = []
        var anySettable = false
        for var addr in volumeAddresses(dev) {
            if isSettable(dev, &addr) { anySettable = true }
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { values.append(v) }
        }
        guard anySettable, !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float32(values.count)
    }

    private func attachVolumeListener(_ dev: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.reload() }
        }
        volumeListener = block
        listenedDevice = dev
        listenedAddresses = volumeAddresses(dev)
        var mute = Self.muteAddress
        if AudioObjectHasProperty(dev, &mute) { listenedAddresses.append(mute) }
        for var addr in listenedAddresses {
            AudioObjectAddPropertyListenerBlock(dev, &addr, .main, block)
        }
    }

    private func detachVolumeListener() {
        guard let block = volumeListener, listenedDevice != kAudioObjectUnknown else { return }
        for var addr in listenedAddresses {
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &addr, .main, block)
        }
        volumeListener = nil
        listenedDevice = AudioObjectID(kAudioObjectUnknown)
        listenedAddresses = []
    }

    private static func name(of dev: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &cf) == noErr, let cf else { return "" }
        return cf.takeRetainedValue() as String
    }

    private static func symbol(of dev: AudioObjectID, name: String) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &t)
        switch t {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            let n = name.lowercased()
            return ["buds", "pods", "qcy", "tws", "earbud"].contains { n.contains($0) } ? "earbuds" : "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker"
        default: return "speaker.wave.2"
        }
    }
}

/// Denetim Merkezi tarzi ses karosu: sol hoparlor, dolgulu kaydirici, sagda cikis aygiti simgesi.
struct VolumeTile: View {
    let volume: SystemVolume
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var speakerSymbol: String {
        switch volume.level {
        case ..<0.001: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ses").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                slider
                Button {
                    volume.toggleOutput()
                } label: {
                    Image(systemName: volume.outputSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                        .glassCircle(interactive: volume.headphoneAvailable)
                }
                .buttonStyle(PressableStyle())
                .disabled(!volume.headphoneAvailable)
                .opacity(volume.headphoneAvailable ? 1 : 0.6)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: volume.outputSymbol)
                .help(volume.headphoneActive ? "Sesi Mac hoparlörüne al" : "Sesi kulaklığa al")
                .accessibilityLabel(volume.headphoneActive ? "Sesi Mac hoparlörüne al" : "Sesi kulaklığa al")
                .accessibilityValue(volume.outputName)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile()
    }

    private var slider: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillW = max(32, w * volume.level)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.white).frame(width: fillW)
                Image(systemName: speakerSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .frame(width: 32, height: 32)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                volume.set(g.location.x / max(w, 1))
            })
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Ses")
        .accessibilityValue("%\(Int((volume.level * 100).rounded()))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: volume.set(volume.level + 0.0625)
            case .decrement: volume.set(volume.level - 0.0625)
            @unknown default: break
            }
        }
    }
}
