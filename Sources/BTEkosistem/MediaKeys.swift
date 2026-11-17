// Telefondan gelen media.cmd komutunu Mac'te sistem medya tusu olarak uygular.
// NOT: Ozel/ucuncu taraf MediaRemote kullanilmaz. Sistem tusu olayi CGEvent ile yayinlanir (.cghidEventTap);
// bu genelde ek izin istemez (Erisilebilirlik gerekmeyebilir) ancak hangi uygulamanin tepki verecegini macOS
// ("Now Playing" uygulamasi) belirler. Bazi macOS surumlerinde olay yayini icin Erisilebilirlik/Input Monitoring
// izni gerekebilir: cihazda dogrulanmadi.
import AppKit

enum MediaKeys {
    private static let play = 16, next = 17, previous = 18   // NX_KEYTYPE_PLAY / NEXT / PREVIOUS

    @MainActor
    static func perform(_ command: String) {
        switch command {
        case "oynat_duraklat", "oynat", "duraklat": press(play)   // Mac'te oynat/duraklat tek tustur (degisken)
        case "sonraki": press(next)
        case "onceki": press(previous)
        default: break
        }
    }

    private static func press(_ key: Int) {
        for down in [true, false] {
            let flags = down ? 0xA00 : 0xB00
            let data1 = (key << 16) | flags
            guard let e = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                             modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                                             timestamp: 0, windowNumber: 0, context: nil,
                                             subtype: 8, data1: data1, data2: -1) else { continue }
            e.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
