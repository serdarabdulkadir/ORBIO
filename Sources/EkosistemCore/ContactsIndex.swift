// Mac tarafi kisi onbellegi arama dizini. Yalniz bellekte; diske yazilmaz. Saf deger tipi, test edilebilir.
import Foundation

public enum ContactText {
    /// Aksan ve buyuk/kucuk harf duyarsiz kanonik metin (Turkce: I, i, ı, İ -> i; ş,ğ,ç,ö,ü -> s,g,c,o,u).
    public static func fold(_ text: String) -> String {
        var t = ""
        t.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "I", "ı", "İ": t.append("i")
            default: t.append(ch)
            }
        }
        return t.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// Yalniz rakamlar (numara karsilastirmasi icin).
    public static func digits(_ text: String) -> String { text.filter { $0.isASCII && $0.isNumber } }

    /// Iki numara ayni hat mi: son 10 hane esit (ulke kodu / baslangic sifiri farkini yok sayar). En az 7 hane.
    public static func sameNumber(_ a: String, _ b: String) -> Bool {
        let x = digits(a), y = digits(b)
        guard x.count >= 7, y.count >= 7 else { return !x.isEmpty && x == y }
        return x.suffix(10) == y.suffix(10)
    }

    /// Avatar baş harfi (ilk harf, buyuk).
    public static func initial(_ name: String) -> String? {
        name.first(where: \.isLetter).map { String($0).uppercased() }
    }
}

public struct ContactsIndex: Sendable {
    private struct Entry: Sendable {
        let record: ContactRecord
        let name: String      // katlanmis ad
        let digits: [String]  // her numaranin rakamlari
    }

    private var entries: [Entry] = []
    private var sorted: [ContactRecord] = []
    private var byLastDigits: [String: Int] = [:]   // son 10 hane -> entries indeksi

    public init() {}
    public init(_ records: [ContactRecord]) { sync(with: records) }

    public var count: Int { entries.count }

    public mutating func reset() { entries = []; sorted = []; byLastDigits = [:] }

    /// Artimli: yalniz kaynak listenin yeni eklenen kuyrugunu isler. Kaynak kisaldiysa bastan kurar.
    public mutating func sync(with records: [ContactRecord]) {
        if records.count < entries.count { reset() }
        guard records.count > entries.count else { return }
        defer { sorted = entries.sorted { $0.name < $1.name }.map(\.record) }
        for r in records[entries.count...] {
            let digs = r.numaralar.map { ContactText.digits($0.no) }
            entries.append(Entry(record: r, name: ContactText.fold(r.ad), digits: digs))
            let idx = entries.count - 1
            for d in digs where d.count >= 7 {
                let key = String(d.suffix(10))
                if byLastDigits[key] == nil { byLastDigits[key] = idx }
            }
        }
    }

    /// Ada gore sirali (katlanmis ad); her senkronda bir kez hesaplanir.
    public var all: [ContactRecord] { sorted }

    public var favorites: [ContactRecord] { all.filter(\.favori) }

    /// Isim ya da numara aramasi. Her sozcuk adda (alt dize) ya da (rakamlarsa) bir numarada gecmeli.
    /// Bos sorgu = tum kisiler. Sonuc: once ad on eki eslesenler, sonra alfabetik.
    public func search(_ query: String) -> [ContactRecord] {
        let q = ContactText.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !q.isEmpty else { return all }
        var hits: [(Entry, Bool)] = []
        for e in entries {
            var ok = true
            var prefix = false
            for tok in q {
                let inName = e.name.contains(tok)
                let dTok = ContactText.digits(tok)
                let inNum = !dTok.isEmpty && dTok.count == tok.filter({ $0 != "+" && $0 != "-" }).count && e.digits.contains { $0.contains(dTok) }
                if !inName && !inNum { ok = false; break }
                if inName, e.name.hasPrefix(tok) || e.name.contains(" " + tok) { prefix = true }
            }
            if ok { hits.append((e, prefix)) }
        }
        return hits.sorted { a, b in
            if a.1 != b.1 { return a.1 }
            return a.0.name < b.0.name
        }.map { $0.0.record }
    }

    /// Numaradan kisi (gelen arama karti / son aramalar icin).
    public func match(number: String?) -> ContactRecord? {
        guard let number else { return nil }
        let d = ContactText.digits(number)
        if d.count >= 7, let i = byLastDigits[String(d.suffix(10))] { return entries[i].record }
        guard !d.isEmpty else { return nil }
        return entries.first { $0.digits.contains(d) }?.record
    }
}

/// "Son aranan" listesi: ayni numara bir kez (en yeni), en yeni basta.
public enum RecentCalls {
    public static func distinct(_ log: [CallLogEntry], limit: Int) -> [CallLogEntry] {
        var seen: [String] = []
        var out: [CallLogEntry] = []
        for e in log.sorted(by: { $0.zaman > $1.zaman }) {
            let d = ContactText.digits(e.numara)
            let key = d.isEmpty ? e.numara : String(d.suffix(10))
            if seen.contains(key) { continue }
            seen.append(key)
            out.append(e)
            if out.count >= limit { break }
        }
        return out
    }
}
