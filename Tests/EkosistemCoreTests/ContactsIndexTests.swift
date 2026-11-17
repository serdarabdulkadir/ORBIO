import Testing
import Foundation
@testable import EkosistemCore

private func c(_ kid: String, _ ad: String, _ nums: [String], fav: Bool = false) -> ContactRecord {
    ContactRecord(kid: kid, ad: ad, numaralar: nums.map { ContactNumber(no: $0, tur: "cep") }, favori: fav)
}

private let sample = [
    c("1", "Işık Çelik", ["+90 532 111 22 33"], fav: true),
    c("2", "İbrahim Öztürk", ["0555 444 33 22", "0212 999 88 77"]),
    c("3", "Ayşe Yılmaz", ["+90 505 000 11 22"]),
    c("4", "Zeynep", ["+1 (415) 555-0100"], fav: true),
]

@Test func aramaAksanVeHarfDuyarsiz() {
    let idx = ContactsIndex(sample)
    #expect(idx.search("isik").map(\.kid) == ["1"])
    #expect(idx.search("IŞIK").map(\.kid) == ["1"])
    #expect(idx.search("ışık çelik").map(\.kid) == ["1"])
    #expect(idx.search("ibrahim").map(\.kid) == ["2"])
    #expect(idx.search("ozturk").map(\.kid) == ["2"])
    #expect(idx.search("ayse yilm").map(\.kid) == ["3"])
    #expect(idx.search("zzz").isEmpty)
}

@Test func aramaNumaradaBosSorguTumunuVerir() {
    let idx = ContactsIndex(sample)
    #expect(idx.search("555 444").map(\.kid) == ["2"])
    #expect(idx.search("5550100").map(\.kid) == ["4"])   // ayraclar yok sayilir, rakam dizisi eslesir
    #expect(idx.search("4155550100").map(\.kid) == ["4"])
    #expect(idx.search("").count == 4)
    #expect(idx.search("  ").count == 4)
}

@Test func siralamaOnEkOnceVeFavoriler() {
    let idx = ContactsIndex([c("a", "Mehmet Ali", ["1111111"]), c("b", "Ali Veli", ["2222222"]), c("c", "Kalite", ["3333333"])])
    #expect(idx.search("ali").map(\.kid) == ["b", "a", "c"])
    #expect(ContactsIndex(sample).favorites.map(\.kid) == ["1", "4"])
}

@Test func numaradanKisiEslestirme() {
    let idx = ContactsIndex(sample)
    #expect(idx.match(number: "0532 111 22 33")?.kid == "1")
    #expect(idx.match(number: "+905321112233")?.kid == "1")
    #expect(idx.match(number: "02129998877")?.kid == "2")
    #expect(idx.match(number: "+905000000000") == nil)
    #expect(idx.match(number: nil) == nil)
    #expect(ContactText.sameNumber("0532 111 22 33", "+90 532 111 22 33"))
    #expect(!ContactText.sameNumber("5321112233", "5321112244"))
}

@Test func artimliEklemeVeKisalirsaYenidenKurma() {
    var idx = ContactsIndex()
    idx.sync(with: Array(sample.prefix(2)))
    #expect(idx.count == 2)
    idx.sync(with: sample)
    #expect(idx.count == 4)
    idx.sync(with: Array(sample.prefix(1)))
    #expect(idx.count == 1)
}

@Test func sonArananlarTekrarsiz() {
    let log = [
        CallLogEntry(numara: "+905321112233", yon: .giden, zaman: 100, sureSn: 1),
        CallLogEntry(numara: "05321112233", yon: .cevapsiz, zaman: 300, sureSn: 0),
        CallLogEntry(numara: "4443332", yon: .gelen, zaman: 200, sureSn: 5),
    ]
    let r = RecentCalls.distinct(log, limit: 5)
    #expect(r.map(\.zaman) == [300, 200])
    #expect(RecentCalls.distinct(log, limit: 1).count == 1)
}
