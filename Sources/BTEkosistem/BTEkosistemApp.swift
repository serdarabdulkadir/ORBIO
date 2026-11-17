// Menu cubugu uygulamasi: Dock simgesi yok, MenuBarExtra(.window) + Ayarlar sahnesi.
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }
}

struct BTEkosistemApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            // Gelen aramada telefon simgesi, aksi halde AirPods Pro simgesi.
            Image(systemName: model.phone.isRinging ? "phone.fill" : "airpods.pro")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
