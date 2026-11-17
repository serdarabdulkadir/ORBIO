import Testing
@testable import EkosistemCore

@Suite("Kontrol sahipligi")
struct ControlOwnershipTests {
    @Test func ilkYoneten() {
        #expect(ControlOwnership.resolve(current: .none, claimant: .phone, userInitiated: false) == .phone)
        #expect(ControlOwnership.resolve(current: .none, claimant: .mac, userInitiated: false) == .mac)
    }
    @Test func digerZorlaAlamaz() {
        #expect(ControlOwnership.resolve(current: .phone, claimant: .mac, userInitiated: false) == .phone)
        #expect(ControlOwnership.resolve(current: .mac, claimant: .phone, userInitiated: false) == .mac)
    }
    @Test func dugmeElDegistirir() {
        #expect(ControlOwnership.resolve(current: .phone, claimant: .mac, userInitiated: true) == .mac)
        #expect(ControlOwnership.resolve(current: .mac, claimant: .phone, userInitiated: true) == .phone)
    }
    @Test func sahipKopunca() {
        #expect(ControlOwnership.afterLoss(current: .phone, lost: .phone) == .none)
        #expect(ControlOwnership.afterLoss(current: .mac, lost: .phone) == .mac)
    }
    @Test func esitZamanlamaMacOncelikli() {
        #expect(ControlOwnership.simultaneousClaim() == .mac)
    }
    @Test func otomatikGatt() {
        #expect(!ControlOwnership.macMayAutoConnect(current: .phone))
        #expect(ControlOwnership.macMayAutoConnect(current: .none))
        #expect(ControlOwnership.macMayAutoConnect(current: .mac))
    }
}
