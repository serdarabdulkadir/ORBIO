// Ayarlar sahnesi: NavigationSplitView; kenar cubugunda cihazlar + Telefon + Genel, ayrinti gruplu form.
import SwiftUI
import EkosistemCore

struct SettingsView: View {
    let model: AppModel
    /// Secili satir: cihaz kimligi, `telefonID` ya da `genelID`.
    @State private var selection: String?

    private static let genelID = "__genel__"
    private static let telefonID = "__telefon__"

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 640)
        .background(WindowTitle(title: "ORBIO Ayarları"))
        .onAppear {
            if selection == nil { selection = (model.primary ?? model.engine.devices.first)?.id ?? Self.genelID }
        }
        .onChange(of: selection) { _, new in
            if let new, model.engine.devices.contains(where: { $0.id == new }) { model.selectedID = new }
        }
    }

    // MARK: Kenar cubugu

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Cihazlar") {
                let devices = model.engine.devices
                if devices.isEmpty {
                    Text("Henüz cihaz yok").foregroundStyle(.tertiary)
                }
                ForEach(devices) { d in
                    Label {
                        Text(d.name).lineLimit(1).truncationMode(.tail)
                    } icon: {
                        Image(systemName: d.symbol)
                    }
                    .badge(d.state == .bagliBuMac ? Text("Bağlı") : nil)
                    .frame(minHeight: 28)
                    .tag(d.id)
                    .accessibilityLabel("\(d.name), \(d.state.label)")
                }
            }
            Section {
                Label("Telefon", systemImage: "smartphone").frame(minHeight: 28).tag(Self.telefonID)
                Label("Genel", systemImage: "gearshape").frame(minHeight: 28).tag(Self.genelID)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Ayrinti

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case Self.genelID:
            GeneralSettingsPage(model: model)
        case Self.telefonID:
            ScrollView { PhoneSettingsView(model: model).padding(20) }
                .navigationTitle("Telefon")
        default:
            if let d = model.engine.devices.first(where: { $0.id == selection }) ?? model.primary ?? model.engine.devices.first {
                DeviceSettingsPage(model: model, device: d, onForget: { selection = Self.genelID })
                    .id(d.id)
            } else {
                emptyDevices
            }
        }
    }

    private var emptyDevices: some View {
        ContentUnavailableView("Henüz cihaz yok", systemImage: "headphones",
                               description: Text("Bluetooth ile eşleşmiş bir kulaklık bulunduğunda burada görünür."))
    }
}

/// Ayarlar penceresinin basligini sistem dilinden bagimsiz Turkce yapar.
private struct WindowTitle: NSViewRepresentable {
    let title: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        Task { @MainActor in view.window?.title = title }
    }
}
