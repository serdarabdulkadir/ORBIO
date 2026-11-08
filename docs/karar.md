# Platform karari (2026-11-08)

## Karar
1. **Ana uygulama: macOS menu cubugu uygulamasi**, Swift 6 + SwiftUI (`MenuBarExtra`), Bluetooth icin CoreBluetooth (BLE tarama, ANCS, kendi GATT servisimiz) + IOBluetooth (Classic baglan / kopar, HFP). Hedef macOS 15+ (kullanicida macOS 27; Xcode ve Swift 6.4 kurulu).
2. **Cekirdek mantik platformdan bagimsiz Swift paketi** (`EkosistemCore`): reklam paketi cozuculeri, cihaz modeli, gecis kurallari. Testlenebilir, uygulama kabugundan ayri.
3. **Android yardimci uygulama (ikinci faz)**: Kotlin + Jetpack Compose. Gorevi: telefonun bildirim / cagri durumunu Mac'e iletmek, "ses kimde" koordinasyonu, Android tarafinda AirPods pil / ANC (LibrePods yontemiyle, kendi kodumuzla).
4. **Mac <-> telefon kanali**: once yerel ag (Bonjour + TLS, ilk eslestirmede 6 haneli kod), yedek olarak BLE GATT. Bulut sunucu yok, hesap yok.

## Neden
- Kullanici Mac kullaniyor; Apple deneyiminin "merkezi" menu cubugu + kapak acilinca kart. Bunu yerel dilde ancak SwiftUI dogru verir (Electron / Flutter macOS'ta yabanci durur ve Bluetooth erisimi zayif).
- Apple'in taklit edilemeyen parcalari (iCloud anahtarli otomatik gecis, Handoff, Find My) bilerek kapsam disi; onlarin yerine kendi koordinasyon kanalimiz. Bu hem yasal / etik sinira uyar hem karisik (Apple + Android + 3. parti kulaklik) cihazlarda calisir.
- Cekirdegin ayri paket olmasi, cozucunun kendi cihaz kayitlariyla birim testlenmesini saglar; uygulama kabugu degisse de mantik kalir.

## Alternatifler (kullaniciya sorulacak)
- A) Yalnizca Mac (AirPods / 3. parti kulaklik + Mac), telefon yok: en hizli yol, bildirim / cagri aktarimi yok.
- B) Mac + Android (bu karar): tam deneyim, iki kod tabani.
- C) Mac + iPhone: iPhone tarafinda Apple zaten cogunu yapiyor; deger kazanci az, ANCS ile bildirim yine alinabilir.
- D) Windows destegi: kapsam disi, istenirse cekirdek mantik Rust / C# ile yeniden yazilir.

## Riskler
- macOS CoreBluetooth Apple'in kendi reklamlarini filtreliyorsa pil karti icin sistem pil degerine dusulur.
- Mac App Store'a uygunluk: IOBluetooth ve arka plan tarama nedeniyle dagitim imzali DMG (notarize) olarak dusunuluyor; yayin karari kullanicida.
- Android 12+ Bluetooth baglanti API'leri bazi uretici ROM'larinda kisitli; CompanionDeviceManager ile denenecek.
