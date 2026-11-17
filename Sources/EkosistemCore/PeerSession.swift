import Foundation

// El sikisma -> SAS onayi -> sifreli oturum durum makinesi. Ag yok: bayt girer, cerceveli bayt cikar.

public enum PeerSessionState: Equatable, Sendable {
    case baslangic, elSikismaBekliyor, sasBekliyor, kurulu, kapali
}

public enum PeerSessionError: Error, Equatable, Sendable {
    case yanlisDurum
    case gecersizElSikisma
    case surumUyusmuyor
    case ayniRol
    case anahtarUyusmuyor      // sabitlenmis anahtar ile gelen anahtar farkli
    case sasReddedildi
    case kodGerekli            // Mac'te aktif eslesme kodu var, telefon kod yollamadi
    case kodYanlis
    case kodKilitlendi
    case cerceve(PeerFrameError)
    case sifre(PeerCryptoError)
    case gecersizMesaj
}

public enum PeerSessionEvent: Equatable, Sendable {
    /// Ilk eslesme: iki ekranda ayni kod gorulup onaylanmali (`confirmSAS`).
    case sasGerekli(code: String, peerKey: Data)
    /// Sifreli oturum hazir. Uygulama `peerKey`i sabitler (ilk eslesmede).
    case kuruldu(peerKey: Data, peerName: String)
    case mesaj(PeerEnvelope)
    /// Dogrulanmis ama taninmayan mesaj tipi (olumcul degil; `error` {kod:"bilinmeyen_tip"} ile yanitlanir).
    case bilinmeyenTip(String)
    case kapandi(PeerSessionError)
}

public struct PeerSessionOutput: Equatable, Sendable {
    /// Karsi tarafa sirayla yazilacak, uzunluk onekli cerceveler.
    public var frames: [Data] = []
    public var events: [PeerSessionEvent] = []
    public init() {}
}

struct PeerHandshake: Codable, Equatable {
    var t = "hs"
    var v: Int
    var rol: String
    var pub: String     // base64, 65 bayt X9.63
    var nonce: String   // base64, 16 bayt
    var ad: String
    var kod: String?    // base64 kod kaniti (yalniz kapi arkasindaki ilk eslesmede telefon yollar)
}

/// Mac kapiyi reddederken el sikisma yerine yolladigi acik, bilgi amacli cerceve (sifreli kanal yok).
struct PeerHandshakeRefusal: Codable, Equatable {
    var t = "hs_red"
    var neden: String
}

public struct PeerSession: Sendable {
    public static let protocolVersion = 1

    public private(set) var state: PeerSessionState = .baslangic
    public let role: PeerRole

    private let identity: PeerIdentity
    private let hello: PeerHello
    private let pinnedPeerKey: Data?
    private let localNonce: Data
    private let pairingGate: PairingGate?
    private let pairingProof: String?
    private var buffer = PeerFrameBuffer()
    private var cipher: PeerCipher?
    private var peerKey = Data()
    private var peerName = ""
    private var held: [PeerEnvelope] = []

    /// `pinnedPeerKey`: onceden eslesmis karsi tarafin acik anahtari (yoksa ilk eslesme, SAS gerekir).
    public init(role: PeerRole, identity: PeerIdentity, hello: PeerHello,
                pinnedPeerKey: Data? = nil, nonce: Data = PeerCrypto.randomNonce(),
                pairingGate: PairingGate? = nil, pairingCode: String? = nil) {
        self.role = role; self.identity = identity; self.hello = hello
        self.pinnedPeerKey = pinnedPeerKey; self.localNonce = nonce
        self.pairingGate = pairingGate
        self.pairingProof = pairingCode.map {
            PairingGate.proof(code: $0, phonePublicKey: identity.publicKey, phoneNonce: nonce).base64EncodedString()
        }
    }

    /// Baglanti kurulunca iki taraf da cagirir; ilk cerceveyi (el sikisma) uretir.
    public mutating func start() -> PeerSessionOutput {
        var out = PeerSessionOutput()
        guard state == .baslangic else { return fail(.yanlisDurum) }
        let hs = PeerHandshake(v: Self.protocolVersion, rol: role.rawValue,
                               pub: identity.publicKey.base64EncodedString(),
                               nonce: localNonce.base64EncodedString(), ad: hello.ad,
                               kod: role == .telefon ? pairingProof : nil)
        do {
            let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
            out.frames.append(try PeerFrame.encode(try e.encode(hs)))
        } catch { return fail(.gecersizElSikisma) }
        state = .elSikismaBekliyor
        return out
    }

    /// Aginizdan gelen ham baytlar (parca olabilir).
    public mutating func receive(_ bytes: Data) -> PeerSessionOutput {
        var out = PeerSessionOutput()
        guard state != .kapali else { return out }
        let frames: [Data]
        do { frames = try buffer.append(bytes) }
        catch let e as PeerFrameError { return fail(.cerceve(e)) }
        catch { return fail(.gecersizMesaj) }
        for frame in frames {
            guard state != .kapali else { break }
            handle(frame, into: &out)
        }
        return out
    }

    /// Kullanici SAS kodunu iki ekranda karsilastirip karar verdi.
    public mutating func confirmSAS(accepted: Bool) -> PeerSessionOutput {
        guard state == .sasBekliyor else { return fail(.yanlisDurum) }
        guard accepted else { return fail(.sasReddedildi) }
        var out = PeerSessionOutput()
        establish(into: &out)
        for env in held where state == .kurulu { out.events.append(.mesaj(env)) }
        held = []
        return out
    }

    /// Kurulu oturumda mesaj gonderir; cerceveli bayt dondurur.
    public mutating func send(_ envelope: PeerEnvelope) throws -> Data {
        guard state == .kurulu else { throw PeerSessionError.yanlisDurum }
        do {
            let packet = try cipher!.seal(try PeerCodec.encode(envelope))
            return try PeerFrame.encode(packet)
        } catch let e as PeerCryptoError { throw PeerSessionError.sifre(e) }
        catch let e as PeerFrameError { throw PeerSessionError.cerceve(e) }
        catch { throw PeerSessionError.gecersizMesaj }
    }

    // MARK: Ic

    private mutating func fail(_ error: PeerSessionError) -> PeerSessionOutput {
        state = .kapali; cipher = nil; held = []
        var out = PeerSessionOutput()
        out.events.append(.kapandi(error))
        return out
    }

    private mutating func establish(into out: inout PeerSessionOutput) {
        state = .kurulu
        if let frame = try? send(PeerEnvelope(.hello(hello))) { out.frames.append(frame) }
        out.events.append(.kuruldu(peerKey: peerKey, peerName: peerName))
    }

    private mutating func handle(_ frame: Data, into out: inout PeerSessionOutput) {
        switch state {
        case .baslangic, .kapali: out = merge(out, fail(.yanlisDurum))
        case .elSikismaBekliyor: handleHandshake(frame, into: &out)
        case .sasBekliyor, .kurulu: handleEncrypted(frame, into: &out)
        }
    }

    private func merge(_ a: PeerSessionOutput, _ b: PeerSessionOutput) -> PeerSessionOutput {
        var r = a; r.frames += b.frames; r.events += b.events; return r
    }

    private mutating func handleHandshake(_ frame: Data, into out: inout PeerSessionOutput) {
        guard let hs = try? JSONDecoder().decode(PeerHandshake.self, from: frame), hs.t == "hs",
              let pub = Data(base64Encoded: hs.pub), pub.count == 65,
              let nonce = Data(base64Encoded: hs.nonce), nonce.count == PeerCrypto.nonceLength else {
            out = merge(out, fail(.gecersizElSikisma)); return
        }
        guard hs.v == Self.protocolVersion else { out = merge(out, fail(.surumUyusmuyor)); return }
        guard hs.rol != role.rawValue, PeerRole(rawValue: hs.rol) != nil else { out = merge(out, fail(.ayniRol)); return }
        if let pinned = pinnedPeerKey, pinned != pub { out = merge(out, fail(.anahtarUyusmuyor)); return }
        if pinnedPeerKey == nil, role == .mac, let gate = pairingGate {
            let result = gate.verify(proof: hs.kod.flatMap { Data(base64Encoded: $0) }, phonePublicKey: pub, phoneNonce: nonce)
            if result != .kabul {
                let (error, neden): (PeerSessionError, String) = switch result {
                case .yanlis: (.kodYanlis, "kod_yanlis")
                case .kilitlendi, .kilitli: (.kodKilitlendi, "kilitli")
                default: (.kodGerekli, "kod_gerekli")
                }
                var failed = fail(error)
                let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
                if let data = try? e.encode(PeerHandshakeRefusal(neden: neden)), let frame = try? PeerFrame.encode(data) {
                    failed.frames.append(frame)
                }
                out = merge(out, failed); return
            }
        }
        do {
            let keys = try PeerCrypto.deriveKeys(
                role: role, identity: identity, peerPublicKey: pub,
                macNonce: role == .mac ? localNonce : nonce,
                phoneNonce: role == .mac ? nonce : localNonce)
            cipher = PeerCipher(role: role, keys: keys)
            peerKey = pub; peerName = hs.ad
            if pinnedPeerKey != nil {
                establish(into: &out)
            } else {
                state = .sasBekliyor
                out.events.append(.sasGerekli(code: keys.sas, peerKey: pub))
            }
        } catch let e as PeerCryptoError {
            out = merge(out, fail(.sifre(e)))
        } catch {
            out = merge(out, fail(.gecersizElSikisma))
        }
    }

    private mutating func handleEncrypted(_ frame: Data, into out: inout PeerSessionOutput) {
        let plain: Data
        do { plain = try cipher!.open(frame) }
        catch let e as PeerCryptoError { out = merge(out, fail(.sifre(e))); return }
        catch { out = merge(out, fail(.gecersizMesaj)); return }
        do {
            let env = try PeerCodec.decode(plain)
            if state == .sasBekliyor { held.append(env) } else { out.events.append(.mesaj(env)) }
        } catch PeerMessageError.bilinmeyenTip(let t) {
            if state == .kurulu { out.events.append(.bilinmeyenTip(t)) }
        } catch {
            out = merge(out, fail(.gecersizMesaj))
        }
    }
}
