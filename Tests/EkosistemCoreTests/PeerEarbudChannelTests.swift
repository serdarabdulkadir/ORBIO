import Testing
import Foundation
import Synchronization
@testable import EkosistemCore

/// Gonderilen zarflari akitan sahte gonderici.
private func makeBroker() -> (PeerRequestBroker, AsyncStream<PeerEnvelope>) {
    let (stream, cont) = AsyncStream.makeStream(of: PeerEnvelope.self)
    let broker = PeerRequestBroker(sender: { env in cont.yield(env); return true })
    return (broker, stream)
}

private func firstSent(_ stream: AsyncStream<PeerEnvelope>) async -> PeerEnvelope? {
    var it = stream.makeAsyncIterator()
    return await it.next()
}

@Test func baglantiYokkenKanalKullanilamaz() async {
    let (broker, _) = makeBroker()
    let ch = PeerEarbudChannel(transport: broker)
    #expect(await ch.isAvailable == false)
    await broker.setConnected(true)
    #expect(await ch.isAvailable == true)
    await broker.setConnected(false)
    #expect(await ch.isAvailable == false)
}

@Test func birakIstegiTamamYanitiylaBiter() async throws {
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    let task = Task { try await ch.requestRelease(deviceID: "AA:BB") }
    let sent = try #require(await firstSent(stream))
    #expect(sent.message == .earbudRelease(EarbudRelease(cihazAdresi: "AA:BB")))
    let id = try #require(sent.id)
    #expect(await broker.handle(PeerEnvelope(.earbudReleaseResult(EarbudResult(sonuc: .tamam)), id: id)))
    try await task.value
    #expect(await broker.pendingCount == 0)
}

@Test func desteklenmiyorYaniti_motoraHataOlarakGider() async throws {
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    let task = Task { try await ch.requestRelease(deviceID: "x") }
    let id = try #require(await firstSent(stream)?.id)
    await broker.handle(PeerEnvelope(.earbudReleaseResult(EarbudResult(sonuc: .desteklenmiyor)), id: id))
    await #expect(throws: PeerChannelError.desteklenmiyor) { try await task.value }
}

@Test func uzakHataYanitiFirlatir() async throws {
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    let task = Task { try await ch.requestConnect(deviceID: "x") }
    let id = try #require(await firstSent(stream)?.id)
    await broker.handle(PeerEnvelope(.error(PeerError(kod: "mesgul", mesaj: "")), id: id))
    await #expect(throws: PeerChannelError.uzak(kod: "mesgul", mesaj: "")) { try await task.value }
}

@Test func baglantiKopunceBekleyenIstekBiter() async throws {
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    let task = Task { try await ch.requestConnect(deviceID: "x") }
    _ = await firstSent(stream)
    await broker.setConnected(false)
    await #expect(throws: PeerChannelError.kapandi) { try await task.value }
}

@Test func iptalBekleyenIstegiTemizler() async throws {
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    let task = Task { try await ch.requestConnect(deviceID: "x") }
    _ = await firstSent(stream)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await broker.pendingCount == 0)
}

@Test func yanitOlmayanMesajlarIstegiTamamlamaz() async throws {
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    let task = Task { try await ch.requestConnect(deviceID: "x") }
    let id = try #require(await firstSent(stream)?.id)
    // Telefonun kendi `ping` istegi ayni numarayi tasisa da karismaz.
    #expect(await broker.handle(PeerEnvelope(.ping, id: id)) == false)
    #expect(await broker.handle(PeerEnvelope(.earbudConnectResult(EarbudResult(sonuc: .tamam)), id: id + 99)) == false)
    await broker.handle(PeerEnvelope(.earbudConnectResult(EarbudResult(sonuc: .tamam)), id: id))
    try await task.value
}

@Test func gondermeBasarisizsaIstekHemenBiter() async {
    let broker = PeerRequestBroker(sender: { _ in false })
    await broker.setConnected(true)
    let ch = PeerEarbudChannel(transport: broker)
    await #expect(throws: PeerChannelError.baglantiYok) { try await ch.requestConnect(deviceID: "x") }
}

@Test func motorKanaliylaBirakmaDesteklenmiyorsaIpucunaDuser() async throws {
    // Gercek kanal + TransferEngine: telefon `desteklenmiyor` derse yerel baglanir, sonuc ipucu olur.
    let (broker, stream) = makeBroker()
    await broker.setConnected(true)
    let script = Script()
    let engine = TransferEngine(peer: PeerEarbudChannel(transport: broker), route: FakeRoute(script: script), clock: SystemClock())
    let task = Task { await engine.transfer(deviceID: "AA", to: .buMac, multipoint: false) }
    let id = try #require(await firstSent(stream)?.id)
    await broker.handle(PeerEnvelope(.earbudReleaseResult(EarbudResult(sonuc: .desteklenmiyor)), id: id))
    #expect(await task.value == .ipucu)
    #expect(await script.count("route.connect") == 1)
}
