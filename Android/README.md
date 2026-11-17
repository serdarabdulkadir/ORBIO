# ORBIO - Android

QCY (MeloBuds) kulaklıkları için Kotlin + Jetpack Compose uygulaması. Kulaklığa doğrudan telefon bağlanır. Paket: `com.btekosistem.android`, minSdk 26, targetSdk 35.

## Özellikler
Alt gezinme: **Kulaklık | Telefon | Ayarlar**.

**Kulaklık** (Mac panelinin Android karşılığı)
- Üstte büyük cihaz kartı; tek satırda "Ses: ... · Kontrol: ..." özeti. Ses bağlantısı (klasik Bluetooth: A2DP/HFP) ile kontrol kanalı (BLE GATT A001) ayrıdır: "bağlı" sözcüğü yalnız SES için, GATT için "kontrol kanalı hazır" kullanılır.
- Adım adım akış: Eşleşme (`createBond`, ACTION_BOND_STATE_CHANGED) -> Ses (A2DP/HFP proxy durumu; "Sesi bağla" gizli `connect` yöntemini yansımayla dener) -> Kontrol (GATT). Ses bağlanamazsa "Kulaklığı telefonunuzun Bluetooth ayarlarından bağlayın" kartı ve Bluetooth ayarlarını açan düğme çıkar. Durum, bağlantı değişikliği yayınlarıyla anında güncellenir. Eşleme/profil mantığı `audio/AudioLink.kt` (saf Kotlin, testli).
- Pil karosu (sol/sağ halka, kutu yalnız değer varsa; düşük pil <= %20 ve şarj rozeti), Ses modu seçici (Kapalı / Gürültü engelleme / Şeffaf, kayan seçim) ve gürültü engelleme sahneleri, Ses kaydırıcısı (telefonun medya sesi, AudioManager), yuvarlak düğmeler: Kulak algılama (cihazdan 0x2C okunduysa), Otomatik geçiş (Mac'in kulaklığı alıp bırakma isteklerine izin), Sessiz. "Yakınlık" Mac'e özgüdür, Android'de işlevi olmadığı için yok.
- QCY notu: cihaz bildirimleri gecikmeli/sırasız gelir. Yazılan değer arayüze hemen yansır, yazdıktan sonraki 700 ms içindeki eski bildirimler yok sayılır, 750 ms'de aynı opcode okunup uygulanır (son yazılan kazanır).

**Telefon**
- Telefon durumu (pil, sinyal, ağ), gelen/süren arama kartı (Cevapla / Reddet / Kapat), tuş takımı ile yeni arama, kişi arama, son aramalar (Tümü / Cevapsız). Gelen arama için uygulama içi kart + bildirim (tam ekran değil). Arama durumu: TelephonyCallback (API 31+) / PhoneStateListener.
- Her izin için gerekçeli boş durum; reddedilirse özellik gizlenmez, pasif olur ve "İzin ver" / "Ayarları aç" gösterir.

**Mac bağlantısı** (docs/telefon-kanali.md'ye birebir): NsdManager ile `_btekosistem._tcp` keşfi, TCP istemci, el sıkışma, P-256 ECDH + HKDF + AES-GCM, 6 haneli SAS onayı ("Aynı" / "Farklı"), anahtar sabitleme (anahtar değişirse uyarı, eşlemeyi silmeden bağlanmaz), ping, üstel geri çekilmeli yeniden bağlanma (en çok 30 sn), ön plan servisi (connectedDevice, "Mac'e bağlı" bildirimi). Kimlik anahtarı Android Keystore'daki AES anahtarıyla sarılıp saklanır.
- Mesajlar: phone.state, call.state, call.answer/reject/hangup/dial, contacts.search/result, calllog.recent/result, earbud.state, earbud.release/connect (+ result), perm.state, error.
- Mac yetkileri Ayarlar'da, **varsayılan kapalı**: Aramaları yönet, Kişiler, Arama geçmişi. Kapalıyken (ya da Android izni yokken) ilgili istek `error {kod:"izin_yok"}` alır.
- `earbud.connect`: ses profili telefonda bağlıysa ses odağı alınır (ses sahipliği); değilse gizli A2DP/Headset `connect`. `earbud.release`: gizli `disconnect`. Gizli API yoksa `{sonuc:"desteklenmiyor"}` döner, çökmez.

## Kod yapısı
- `peer/` kanal: `PeerJson`, `PeerMessage` (+codec), `PeerFraming`, `PeerCrypto`, `PeerSession` saf Kotlin (Android'e bağımlı değil, testli). `PeerManager` (döngü, soket), `PeerService`, `MacDiscovery`, `PeerStore`, `PhoneController`, `EarbudBridge` Android katmanı.
- `audio/` ses bağlantısı durum eşleme (saf). `protocol/` QCY protokolü (saf). `ble/` tarayıcı, GATT, ortam. `ui/` Compose; ekranlar durumsuz `*Content` + durum tutan sarmalayıcı, `Previews.kt` sahte verili önizlemeler.
- Tasarım: AimTrack paleti (koyu #000B18, kart #0B1828, açık #F4F5F7), köşe 8/12/18/22, kart köşesi 18 / iç boşluk 16 / karo arası 12, ikonlar Material Symbols/Rounded, hareket 150-250 ms ve sistem animasyon ölçeği 0 ise kapalı.

## Kurulum ve derleme
```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools   # platforms;android-35 ve JDK 17 gerekir
cd Android
./gradlew testDebugUnitTest assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```
`local.properties` (sdk.dir) git'e girmez. Üretim imzası/keystore yoktur.

## İzinler
- Bluetooth: Android 12+ `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`; Android 11 ve öncesi `ACCESS_FINE_LOCATION` + konum servisi.
- Telefon sekmesi (çalışma zamanında, gerekçe ekranıyla): `READ_PHONE_STATE` (arama durumu), `ANSWER_PHONE_CALLS` (cevapla/reddet/kapat; `endCall` API 28+), `CALL_PHONE` (arama başlatma, `TelecomManager.placeCall`), `READ_CALL_LOG` (geçmiş, gelen numara), `READ_CONTACTS` (kişi adı/arama).
- Ağ ve servis: `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `FOREGROUND_SERVICE(_CONNECTED_DEVICE)`, `POST_NOTIFICATIONS` (Mac'e bağlanırken istenir).

## Mac ile eşleştirme
1. Mac'te ORBIO'yu aç, telefonla aynı Wi-Fi'de ol.
2. Telefon sekmesi -> "Mac'e bağlan" (bildirim izni istenir).
3. "Eşleştirilecek Mac" listesinden Mac'i seç -> iki ekranda 6 haneli kod çıkar; aynıysa ikisinde de "Aynı".
4. Ayarlar -> "Mac ile telefon kanalı"ndan Mac'e vereceğin yetkileri aç (hepsi varsayılan kapalı). Eşlemeyi silmek için iki tarafta da sil.

## Sınırlar
- Arama sırasında karşı tarafın açtığı an Android'de bildirilmez (READ_PRECISE_PHONE_STATE ayrıcalıklıdır): giden aramalar "araniyor" kalır.
- Gelen numara bazı cihaz/sürümlerde (Android 9+, READ_CALL_LOG yoksa) boş gelir.
- Android'de başka uygulamanın kulaklığı programla bırakması/bağlaması gizli API'dir; çoğu cihazda çalışmaz ("desteklenmiyor" döner, kullanıcı Bluetooth ayarlarına yönlendirilir).
- İleri gizlilik yok (belge tasarımı: kalıcı kimlik anahtarlarıyla ECDH). Tek Mac eşleşir.
- Gerçek telefon, Mac ve ağda denenmedi; yalnız birim testleri çalıştırıldı.

## Desteklenen cihaz
QCY MeloBuds Pro (reklam paketi ve komutlar bu modelde doğrulandı). Diğer QCY modelleri denenmedi.
