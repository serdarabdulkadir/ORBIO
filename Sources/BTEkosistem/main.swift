// Giris: `--selftest` motoru sahte olay dizisiyle dener ve cikar; aksi halde uygulama baslar.
// Varsayilan: gercek Bluetooth saglayici. `--mock` sahte veriyle acar (tasarim / demo).
import Foundation

if CommandLine.arguments.contains("--kesif") {
    Task { @MainActor in Kesif.run() }
    Task { try? await Task.sleep(for: .seconds(25)); exit(0) }
    dispatchMain()
} else if CommandLine.arguments.contains("--sorgu") {
    Task { @MainActor in Sorgu.run() }
    Task { try? await Task.sleep(for: .seconds(30)); exit(0) }
    dispatchMain()
} else if CommandLine.arguments.contains("--tara") {
    Task { @MainActor in Tara.run(dinle: false) }
    Task { try? await Task.sleep(for: .seconds(60)); exit(0) }
    dispatchMain()
} else if CommandLine.arguments.contains("--dinle") {
    Task { @MainActor in Tara.run(dinle: true) }
    Task { try? await Task.sleep(for: .seconds(140)); exit(0) }
    dispatchMain()
} else if let i = CommandLine.arguments.firstIndex(of: "--seffaf") {
    // Deger 0x00..0x0F disinda ise HICBIR sey baslatilmaz / yazilmaz.
    let arg = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : ""
    let s = arg.lowercased().hasPrefix("0x") ? String(arg.dropFirst(2)) : arg
    let v = UInt8(s, radix: arg.lowercased().hasPrefix("0x") ? 16 : 10)
    guard let v, v <= 0x0F else {
        print("HATA: --seffaf <deger> 0..15 (0x00..0x0F) araliginda olmali: '\(arg)'")
        exit(64)
    }
    Task { @MainActor in Seffaf.run(degerler: [v]) }
    Task { try? await Task.sleep(for: .seconds(40)); exit(0) }
    dispatchMain()
} else if CommandLine.arguments.contains("--seffaf-dene") {
    Task { @MainActor in Seffaf.run(degerler: [0x04, 0x02, 0x06]) }
    Task { try? await Task.sleep(for: .seconds(60)); exit(0) }
    dispatchMain()
} else if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in exit(await runSelfTest()) }
    dispatchMain()
} else {
    BTEkosistemApp.main()
}
