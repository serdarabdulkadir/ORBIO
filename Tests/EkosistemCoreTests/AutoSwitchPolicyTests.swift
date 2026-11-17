import Testing
import Foundation
@testable import EkosistemCore

@Test func hicbirZamanKuraliGecisYapmaz() {
    let p = Box(AutoSwitchPolicy())
    #expect(p.v.callStarted(deviceID: "d", rule: .hicbirZaman, state: .bagliBuMac, at: t0) == nil)
    #expect(p.v.mediaStarted(deviceID: "d", on: .telefon, rule: .hicbirZaman, state: .bagliBuMac, at: t0) == nil)
}

@Test func cagriGelinceMacteykenTelefonaGecer() {
    let p = Box(AutoSwitchPolicy())
    let d = p.v.callStarted(deviceID: "d", rule: .telefondaCagriGelince, state: .bagliBuMac, at: t0)
    #expect(d == AutoSwitchDecision(deviceID: "d", target: .telefon, reason: .cagriGeldi))
    // zaten telefondaysa ya da bagli degilse gecis yok
    #expect(p.v.callStarted(deviceID: "d", rule: .telefondaCagriGelince, state: .bagliTelefon, at: t0) == nil)
    #expect(p.v.callStarted(deviceID: "d", rule: .telefondaCagriGelince, state: .bagliDegil, at: t0) == nil)
}

@Test func cagriBitinceBesSnSonraDonusOnerisi() {
    let p = Box(AutoSwitchPolicy())
    _ = p.v.callStarted(deviceID: "d", rule: .telefondaCagriGelince, state: .bagliBuMac, at: t0)
    p.v.callEnded(deviceID: "d", at: at(100))
    #expect(p.v.dueReturnSuggestions(at: at(104.9)).isEmpty)
    #expect(p.v.dueReturnSuggestions(at: at(105)) == [ReturnSuggestion(deviceID: "d", owner: .buMac)])
    #expect(p.v.dueReturnSuggestions(at: at(200)).isEmpty)  // bir kez
}

@Test func cagriOlmadanBitenCagriOneriUretmez() {
    let p = Box(AutoSwitchPolicy())
    p.v.callEnded(deviceID: "d", at: t0)
    #expect(p.v.dueReturnSuggestions(at: at(10)).isEmpty)
}

@Test func medyaBaslayanTarafaGecerAyniTarafsaGecmez() {
    let p = Box(AutoSwitchPolicy())
    #expect(p.v.mediaStarted(deviceID: "d", on: .buMac, rule: .medyaBaslayanCihaza, state: .bagliBuMac, at: t0) == nil)
    #expect(p.v.mediaStarted(deviceID: "d", on: .telefon, rule: .medyaBaslayanCihaza, state: .bagliBuMac, at: t0)
            == AutoSwitchDecision(deviceID: "d", target: .telefon, reason: .medyaBasladi))
    #expect(p.v.mediaStarted(deviceID: "d", on: .telefon, rule: .medyaBaslayanCihaza, state: .yakinda, at: t0) == nil)
}

@Test func tekrarGecisArasi10Sn() {
    let p = Box(AutoSwitchPolicy())
    let d = AutoSwitchDecision(deviceID: "d", target: .telefon, reason: .medyaBasladi)
    p.v.recordSwitch(d, from: .buMac, at: at(100))
    #expect(p.v.mediaStarted(deviceID: "d", on: .buMac, rule: .medyaBaslayanCihaza, state: .bagliTelefon, at: at(109.9)) == nil)
    #expect(p.v.mediaStarted(deviceID: "d", on: .buMac, rule: .medyaBaslayanCihaza, state: .bagliTelefon, at: at(110)) != nil)
    // baska cihaz etkilenmez
    #expect(p.v.mediaStarted(deviceID: "x", on: .buMac, rule: .medyaBaslayanCihaza, state: .bagliTelefon, at: at(101)) != nil)
}

@Test func geriAlPenceresi30Sn() {
    let p = Box(AutoSwitchPolicy())
    let d = AutoSwitchDecision(deviceID: "d", target: .telefon, reason: .cagriGeldi)
    let offer = p.v.recordSwitch(d, from: .buMac, at: t0)
    #expect(offer.restoreTo == .buMac)
    #expect(p.v.undoOffer(at: at(29.9)) == offer)
    #expect(p.v.undoOffer(at: at(30)) == nil)
    #expect(p.v.consumeUndo(at: at(31)) == nil)
}

@Test func geriAlBirKezKullanilirVeAraligiBaslatir() {
    let p = Box(AutoSwitchPolicy())
    let d = AutoSwitchDecision(deviceID: "d", target: .telefon, reason: .medyaBasladi)
    p.v.recordSwitch(d, from: .buMac, at: t0)
    #expect(p.v.consumeUndo(at: at(5))?.restoreTo == .buMac)
    #expect(p.v.consumeUndo(at: at(6)) == nil)
    #expect(p.v.mediaStarted(deviceID: "d", on: .telefon, rule: .medyaBaslayanCihaza, state: .bagliBuMac, at: at(8)) == nil)
}
