// Telefon sekmesi: kisi arama, Favoriler / Son aranan / Tum kisiler, kisi detayi, serbest numara ve tus takimi.
// Kisi verisi yalniz bellektedir (PhoneModel.contactIndex); diske yazilmaz.
import SwiftUI
import AppKit
import EkosistemCore

/// Kucuk resim onbellegi (bellek): ayni kisi icin base64 her cizimde cozulmesin.
@MainActor
enum ContactPhotoCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(for record: ContactRecord) -> NSImage? {
        guard let b64 = record.foto else { return nil }
        let key = "\(record.kid)|\(b64.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = Data(base64Encoded: b64), let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
    static func clear() { cache.removeAllObjects() }
}

/// Fotograf varsa fotograf, yoksa bas harf avatari.
struct ContactAvatar: View {
    var record: ContactRecord?
    var name: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let record, let img = ContactPhotoCache.image(for: record) {
                Image(nsImage: img).resizable().scaledToFill()
            } else if let c = ContactText.initial(record?.ad ?? name ?? "") {
                Text(c).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: size, height: size).background(Color.blue)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: size, height: size).background(Color.gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

func contactNumberTypeTitle(_ tur: String) -> String {
    switch tur {
    case "cep": "Cep"
    case "ev": "Ev"
    case "is": "İş"
    default: "Diğer"
    }
}

struct PhoneContactsTile: View {
    let phone: PhoneModel
    @State private var query = ""
    @State private var selectedID: String?
    @State private var showKeypad = false

    private var snap: PhoneSnapshot { phone.snapshot }
    private var canDial: Bool { snap.allows(.cagriYonetimi) }
    private var canContacts: Bool { snap.allows(.kisiler) }
    private var canLog: Bool { snap.allows(.aramaGecmisi) }
    private var selected: ContactRecord? { selectedID.flatMap { id in phone.contactIndex.all.first { $0.kid == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TileTitle(text: "Kişiler ve arama")
                Spacer(minLength: 0)
                PillButton(title: showKeypad ? "Tuş takımını gizle" : "Tuş takımı", symbol: "circle.grid.3x3.fill") { showKeypad.toggle() }
            }
            if !canDial { note("Arama başlatmak için telefonda \"Çağrı yönetimi\" iznini açın.") }
            if let c = selected {
                detail(c)
            } else {
                searchField
                if !canContacts { note("Kişileri görmek için telefonda \"Kişiler\" iznini açın; yine de numara yazıp arayabilirsiniz.") }
                content
            }
            if showKeypad { keypad }
            note("Arama telefonda yapılır; ses telefonda ya da kulaklığınızda kalır, bu Mac'in mikrofonu ve hoparlörü kullanılmaz. Kişi bilgisi yalnızca bellekte tutulur, bağlantı kopunca silinir.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
        .animation(.easeOut(duration: 0.15), value: selectedID)
        .onChange(of: phone.isConnected) { _, on in if !on { selectedID = nil; query = ""; ContactPhotoCache.clear() } }
    }

    // MARK: Arama alani

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("İsim veya numara ara", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13))
                .disabled(!phone.isConnected)
                .onSubmit { if let n = freeNumber { place(n) } }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCapsule()
    }

    /// Yazilan metin numara gibiyse (rakam, +, *, #, bosluk, tire, parantez) aranabilir numara.
    private var freeNumber: String? {
        let t = query.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ "0123456789+*#-() ".contains($0) }) else { return nil }
        let n = PhoneModel.dialable(t)
        return n.isEmpty ? nil : n
    }

    private func place(_ number: String) {
        guard canDial else { return }
        phone.dial(number)
        query = ""
        selectedID = nil
    }

    // MARK: Icerik

    @ViewBuilder
    private var content: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            browse
        } else {
            let hits = canContacts ? Array(phone.contactIndex.search(q).prefix(40)) : []
            VStack(alignment: .leading, spacing: 4) {
                if let n = freeNumber {
                    Button { place(n) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(Circle().fill(canDial ? Color.green : Color.gray))
                            Text("\(n) numarasını ara").font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canDial)
                }
                if canContacts && hits.isEmpty && freeNumber == nil { note("Eşleşen kişi yok.") }
                ForEach(hits) { c in contactRow(c) }
            }
        }
    }

    @ViewBuilder
    private var browse: some View {
        let favs = phone.contactIndex.favorites
        let recents = canLog ? RecentCalls.distinct(snap.callLog ?? [], limit: 5) : []
        VStack(alignment: .leading, spacing: 10) {
            if canContacts && snap.contactsLoading && snap.contactBook.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); note("Kişiler yükleniyor…") }
            }
            if !favs.isEmpty {
                section("Favoriler") { ForEach(favs.prefix(8)) { c in contactRow(c) } }
            }
            if canLog {
                section("Son aranan", trailing: AnyView(PillButton(title: "Yenile", symbol: "arrow.clockwise") { phone.refreshCallLog() })) {
                    if recents.isEmpty {
                        note(snap.callLog == nil ? "Arama geçmişi yükleniyor…" : "Arama kaydı yok.")
                    } else {
                        ForEach(Array(recents.enumerated()), id: \.offset) { _, e in recentRow(e) }
                    }
                }
            } else {
                note("Son aranan numaralar için telefonda \"Arama geçmişi\" iznini açın.")
            }
            if canContacts {
                let total = snap.contactsTotal.map { " (\($0))" } ?? ""
                section("Tüm kişiler\(total)", trailing: AnyView(PillButton(title: "Yenile", symbol: "arrow.clockwise") { phone.refreshContacts() })) {
                    let all = phone.contactIndex.all
                    if all.isEmpty && !snap.contactsLoading {
                        note("Kişi yok.")
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(all) { c in contactRow(c) }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
            }
        }
    }

    private func section(_ title: String, trailing: AnyView? = nil, @ViewBuilder _ rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailing
            }
            rows()
        }
    }

    private func contactRow(_ c: ContactRecord) -> some View {
        Button { selectedID = c.kid } label: {
            HStack(spacing: 10) {
                ContactAvatar(record: c, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.ad).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if let n = c.numaralar.first {
                        Text(n.no).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if c.favori { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Kişi ayrıntısını ve numaralarını açar")
    }

    private func recentRow(_ e: CallLogEntry) -> some View {
        let contact = phone.contact(for: e.numara)
        let missed = e.yon == .cevapsiz
        let symbol = e.yon == .giden ? "phone.arrow.up.right" : "phone.arrow.down.left"
        let kind: String = switch e.yon {
        case .gelen: "Gelen"
        case .giden: "Giden"
        case .cevapsiz: "Cevapsız"
        }
        return Button {
            if let contact { selectedID = contact.kid } else { query = e.numara }
        } label: {
            HStack(spacing: 10) {
                ContactAvatar(record: contact, name: e.kisiAdi, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(contact?.ad ?? e.kisiAdi ?? e.numara).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(missed ? Color.red : Color.primary).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: symbol).font(.system(size: 9))
                        Text("\(kind), \(e.sureSn >= 60 ? "\(e.sureSn / 60) dk" : "\(e.sureSn) sn")").font(.system(size: 10))
                    }
                    .foregroundStyle(missed ? Color.red : Color.secondary)
                }
                Spacer(minLength: 6)
                Text(Date(timeIntervalSince1970: TimeInterval(e.zaman)), format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Kisi detayi

    private func detail(_ c: ContactRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { selectedID = nil } label: {
                Label("Kişiler", systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            HStack(spacing: 12) {
                ContactAvatar(record: c, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(c.ad).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        if c.favori { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow) }
                    }
                    if !c.gruplar.isEmpty {
                        Text(c.gruplar.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            if c.numaralar.isEmpty { note("Bu kişinin numarası yok.") }
            ForEach(Array(c.numaralar.enumerated()), id: \.offset) { _, n in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(contactNumberTypeTitle(n.tur)).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(n.no).font(.system(size: 13).monospacedDigit())
                    }
                    Spacer(minLength: 8)
                    Button { place(PhoneModel.dialable(n.no)) } label: {
                        Image(systemName: "phone.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Circle().fill(canDial ? Color.green : Color.gray))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle()).disabled(!canDial)
                    .accessibilityLabel("\(c.ad) kişisini \(contactNumberTypeTitle(n.tur)) numarasından ara")
                }
            }
        }
    }

    // MARK: Tus takimi

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
        return VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        Button { selectedID = nil; query.append(key) } label: {
                            Text(key).font(.system(size: 20, weight: .medium))
                                .frame(width: 48, height: 48).glassCircle().contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            HStack(spacing: 16) {
                Button { if !query.isEmpty { query.removeLast() } } label: {
                    Image(systemName: "delete.left").font(.system(size: 13))
                        .foregroundStyle(query.isEmpty ? Color.secondary.opacity(0.4) : Color.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Sil")
            }
            CallActionButton(title: "Ara", symbol: "phone.fill", color: .green, enabled: canDial && freeNumber != nil) {
                if let n = freeNumber { place(n) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
