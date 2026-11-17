// Veri saglayici sozlesmesi: gercek Bluetooth ya da sahte veri; ikisi de motora DeviceEvent akitir.
import Foundation
import EkosistemCore
import Synchronization

enum PermissionState: Equatable {
    case bekliyor, verildi, reddedildi

    var label: String {
        switch self {
        case .bekliyor: "Bekliyor"
        case .verildi: "Verildi"
        case .reddedildi: "Reddedildi"
        }
    }
}

/// QCY A001 kontrol kanalinin durumu: baglaniyor (ya da veri bekleniyor), hazir, kapali (baglanilamadi / koptu).
enum QcyLinkStatus: Equatable {
    case baglaniyor, hazir, kapali
}

/// Sistemin bildirdigi pil degerleri; saglayici yazar, motor (`systemBattery`) okur.
final class BatteryCache: Sendable {
    private let store = Mutex<[String: BatteryReading]>([:])
    func set(_ reading: BatteryReading, for id: String) { store.withLock { $0[id] = reading } }
    func reading(for id: String) -> BatteryReading? { store.withLock { $0[id] } }
}

@MainActor
protocol DeviceProvider: AnyObject {
    /// Motorun tuketecegi olay akisi.
    var events: AsyncStream<DeviceEvent> { get }
    var audioRoute: any AudioRoute { get }
    var peerChannel: any PeerChannel { get }
    var permission: PermissionState { get }
    var onPermissionChange: (@MainActor (PermissionState) -> Void)? { get set }
    /// Cihazdan okunan QCY durumu (ses modu, sahne, kulak algilama); okuma yaniti ya da cihazda yapilan degisiklik.
    var onQcyState: (@MainActor (_ deviceID: String, _ state: QcyDeviceState) -> Void)? { get set }
    /// A001 kontrol kanalinin durum degisimi.
    var onQcyLink: (@MainActor (_ deviceID: String, _ status: QcyLinkStatus) -> Void)? { get set }
    /// Bu cihaz bir QCY kulaklik mi (ad ya da reklamdan)? Panelde Pil / Ses modu karolari bunlar icin hep gorunur.
    func isQcy(_ deviceID: String) -> Bool
    /// Kontrol kanalini hemen yeniden dener (geri cekilme sayaci sifirlanir).
    func reconnect(_ deviceID: String)
    /// Ses modu cihaza gercekten yazilabiliyor mu (kulaklik tanindi ve ulasilabilir)?
    func supportsListeningControl(_ deviceID: String) -> Bool
    /// Dogrulanmis bir komutu cihaza yazar, ardindan ilgili okumayi ister (yanit `onQcyState` ile gelir); basarisizsa false.
    func send(_ command: QcyCommand, for deviceID: String) async -> Bool
    func start()
    /// "Yenile" dugmesi: durumu ve pili yeniden okur.
    func refresh()
}
