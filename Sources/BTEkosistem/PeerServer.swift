// Telefon kanali agi: NWListener + Bonjour (_btekosistem._tcp), baglanti basina PeerSession (docs/telefon-kanali.md).
// Tasiyici soyut (PeerTransport): TCP ve Bluetooth RFCOMM ayni PeerLink / PeerSession kodunu kullanir.
// Tum geri cagirmalar ana kuyrukta ve ana aktorde calisir.
import Foundation
import Network
import EkosistemCore

/// Tek bir tasiyici (TCP / RFCOMM) + onun sifreli oturumu. Zaman asimlari ve ping burada.
@MainActor
final class PeerLink {
    static let handshakeTimeout: TimeInterval = 10
    static let sasTimeout: TimeInterval = 60
    static let pingInterval: TimeInterval = 15
    static let deadAfter: TimeInterval = 45

    private let transport: any PeerTransport
    var path: PeerPath { transport.path }
    private(set) var establishedAt: Date?
    private(set) var session: PeerSession
    private(set) var closeReason: PeerSessionError?
    private var closed = false
    private var stateSince = Date()
    private var lastState: PeerSessionState = .baslangic
    private var lastReceived = Date()
    private var lastPing = Date()
    private var watchdog: Task<Void, Never>?

    var onOutput: (@MainActor (PeerLink, PeerSessionOutput) -> Void)?
    var onGone: (@MainActor (PeerLink) -> Void)?

    init(transport: any PeerTransport, session: PeerSession) {
        self.transport = transport
        self.session = session
    }

    func begin() {
        transport.onReady = { [weak self] in
            guard let self, !self.closed else { return }
            self.lastReceived = Date()
            self.handle(self.session.start())
        }
        transport.onData = { [weak self] data in
            guard let self, !self.closed else { return }
            self.lastReceived = Date()
            self.handle(self.session.receive(data))
        }
        transport.onClosed = { [weak self] in self?.close() }
        transport.start()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func confirmSAS(accepted: Bool) { handle(session.confirmSAS(accepted: accepted)) }

    /// Kurulu oturumda mesaj gonderir.
    @discardableResult
    func send(_ envelope: PeerEnvelope) -> Bool {
        guard !closed, session.state == .kurulu else { return false }
        do {
            transmit([try session.send(envelope)])
            return true
        } catch {
            close()
            return false
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        watchdog?.cancel()
        transport.close()
        onGone?(self)
    }

    // MARK: Ic

    private func handle(_ output: PeerSessionOutput) {
        transmit(output.frames)
        if session.state == .kurulu, establishedAt == nil { establishedAt = Date() }
        for case .kapandi(let reason) in output.events { closeReason = reason }
        onOutput?(self, output)
        if session.state == .kapali { close() }
    }

    private func transmit(_ frames: [Data]) {
        for f in frames { transport.send(f) }
    }

    private func tick() {
        guard !closed else { return }
        let now = Date()
        if session.state != lastState {
            lastState = session.state
            stateSince = now
            if lastState == .kurulu { lastReceived = now; lastPing = now }
        }
        let waited = now.timeIntervalSince(stateSince)
        switch session.state {
        case .baslangic, .elSikismaBekliyor:
            if waited > Self.handshakeTimeout { close() }
        case .sasBekliyor:
            if waited > Self.sasTimeout { close() }
        case .kurulu:
            if now.timeIntervalSince(lastReceived) > Self.deadAfter { close(); return }
            if now.timeIntervalSince(lastPing) >= Self.pingInterval {
                lastPing = now
                send(PeerEnvelope(.ping))
            }
        case .kapali:
            close()
        }
    }
}

@MainActor
final class PeerServer {
    enum Status: Equatable {
        case durdu, baslatiliyor
        case dinliyor(UInt16)
        case yerelAgReddedildi
        case hata(String)
    }

    /// Dinleyici durumu.
    var onStatus: (@MainActor (Status) -> Void)?
    /// Ilk eslesme: iki ekranda ayni 6 haneli kod onaylanmali.
    var onSAS: (@MainActor (String) -> Void)?
    /// Sifreli oturum hazir (`peerKey` sabitlenmemisse uygulama sabitler).
    var onEstablished: (@MainActor (_ peerKey: Data, _ peerName: String) -> Void)?
    var onMessage: (@MainActor (PeerEnvelope) -> Void)?
    /// Aktif oturum ya da eslesme adayi kapandi. `wasActive == false`: kurulamayan / reddedilen baglanti.
    var onClosed: (@MainActor (_ reason: PeerSessionError?, _ wasActive: Bool) -> Void)?
    /// Aktif oturumun yolu degisti (nil: oturum yok).
    var onPath: (@MainActor (PeerPath?) -> Void)?
    /// Herhangi bir baglanti bitti (yol, oturum ne zaman kurulduysa); Bluetooth geri cekilmesi icin.
    var onLinkEnded: (@MainActor (_ path: PeerPath, _ establishedAt: Date?) -> Void)?

    private(set) var status: Status = .durdu
    var activePath: PeerPath? { active?.path }
    /// Bir baglanti (aday dahil) Bluetooth uzerinden mi?
    var bluetoothBusy: Bool { active?.path == .bluetooth || candidate?.path == .bluetooth }
    private var listener: NWListener?
    private var active: PeerLink?
    private var candidate: PeerLink?
    private var identity: PeerIdentity?
    private var hello: PeerHello?
    private var txt: [String: String] = [:]
    private var serviceName = "Mac"
    private var pinned: Data?
    private var pairingGate: PairingGate?
    private var retry: Task<Void, Never>?

    func configure(identity: PeerIdentity, hello: PeerHello, pinned: Data?, pairingGate: PairingGate? = nil) {
        self.pairingGate = pairingGate
        self.identity = identity
        self.hello = hello
        self.pinned = pinned
        serviceName = String(hello.ad.prefix(40))
        txt = ["ad": hello.ad, "surum": String(PeerSession.protocolVersion), "id": hello.cihazId]
    }

    func setPinned(_ key: Data?) { pinned = key }

    func start() {
        guard listener == nil, identity != nil else { return }
        retry?.cancel()
        set(.baslatiliyor)
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: serviceName, type: "_btekosistem._tcp", txtRecord: NWTXTRecord(txt))
            l.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerState(state) }
            }
            l.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener = l
            l.start(queue: .main)
        } catch {
            set(.hata(error.localizedDescription))
            scheduleRetry()
        }
    }

    func stop() {
        retry?.cancel()
        listener?.cancel()
        listener = nil
        disconnectAll()
        set(.durdu)
    }

    func disconnectAll() {
        let a = active, c = candidate
        active = nil; candidate = nil
        if a != nil { onPath?(nil) }
        a?.close(); c?.close()
    }

    /// Wi-Fi geldi: Bluetooth (RFCOMM) oturumu ve adayi kapanir; Wi-Fi oturumuna dokunulmaz.
    func dropBluetooth() {
        if active?.path == .bluetooth, let a = active {
            active = nil
            onPath?(nil)
            a.close()
            onClosed?(a.closeReason, true)
        }
        if candidate?.path == .bluetooth, let c = candidate { candidate = nil; c.close() }
    }

    /// Mac'in actigi giden tasiyici (RFCOMM): TCP ile ayni oturum koduyla yurur. Wi-Fi oturumu varken ya da
    /// baska aday varken reddedilir.
    @discardableResult
    func adopt(_ transport: any PeerTransport) -> Bool {
        guard identity != nil, active?.path != .wifi, candidate == nil else { transport.close(); return false }
        attach(transport)
        return true
    }

    func confirmSAS(accepted: Bool) { candidate?.confirmSAS(accepted: accepted) }

    @discardableResult
    func send(_ envelope: PeerEnvelope) -> Bool { active?.send(envelope) ?? false }

    // MARK: Ic

    private func set(_ s: Status) {
        status = s
        onStatus?(s)
    }

    private func listenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            set(.dinliyor(listener?.port?.rawValue ?? 0))
        case .waiting(let error):
            set(Self.isLocalNetworkDenied(error) ? .yerelAgReddedildi : .hata(error.localizedDescription))
        case .failed(let error):
            listener?.cancel()
            listener = nil
            set(Self.isLocalNetworkDenied(error) ? .yerelAgReddedildi : .hata(error.localizedDescription))
            scheduleRetry()
        default:
            break
        }
    }

    /// Yerel Ag izni reddedilince Bonjour `kDNSServiceErr_PolicyDenied` (-65570) verir.
    private static func isLocalNetworkDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == -65570 }
        return false
    }

    private func scheduleRetry() {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.start() }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard identity != nil else { connection.cancel(); return }
        // Wi-Fi onceliklidir: Bluetooth adayi Wi-Fi gelince yerini birakir.
        if let c = candidate, c.path == .bluetooth { candidate = nil; c.close() }
        guard candidate == nil else { connection.cancel(); return }
        attach(TcpTransport(connection: connection))
    }

    private func attach(_ transport: any PeerTransport) {
        guard let identity, let hello else { transport.close(); return }
        let link = PeerLink(transport: transport,
                            session: PeerSession(role: .mac, identity: identity, hello: hello, pinnedPeerKey: pinned,
                                                 pairingGate: pairingGate))
        link.onOutput = { [weak self] link, output in self?.output(link, output) }
        link.onGone = { [weak self] link in self?.gone(link) }
        candidate = link
        link.begin()
    }

    private func output(_ link: PeerLink, _ output: PeerSessionOutput) {
        for event in output.events {
            switch event {
            case .sasGerekli(let code, _):
                if link === candidate { onSAS?(code) }
            case .kuruldu(let key, let name):
                if link === candidate {
                    // Ayni (sabitlenmis) telefon yeniden baglandi: eski, takili kalmis oturumun yerini alir.
                    let old = active
                    candidate = nil
                    active = link
                    old?.close()
                    onPath?(link.path)
                }
                onEstablished?(key, name)
            case .mesaj(let envelope):
                if link === active { onMessage?(envelope) }
            case .bilinmeyenTip(let type):
                link.send(PhoneSnapshot.unknownTypeReply(type))
            case .kapandi:
                break   // `gone` icinde ele alinir
            }
        }
    }

    private func gone(_ link: PeerLink) {
        onLinkEnded?(link.path, link.establishedAt)
        if link === active {
            active = nil
            onPath?(nil)
            onClosed?(link.closeReason, true)
        } else if link === candidate {
            candidate = nil
            onClosed?(link.closeReason, false)
        }
    }
}
