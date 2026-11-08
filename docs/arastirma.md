# Arastirma: Apple ekosistemi ozellikleri ve Apple disi uygulanabilirlik

Tarih: 2026-11-08. Kapsam: kullanicinin KENDI cihazlari, yalnizca birlikte calisabilirlik.
Sifreleme / DRM kirma, Apple sunucularina sahte istemci, kimlik taklidi kapsam disidir.
GPL projelerden (LibrePods, OpenPods, CAPod) kod KOPYALANMAZ; yalnizca yontem ogrenilir ve kaynak gosterilir.

Uygulanabilirlik: evet = macOS / Android'de herkese acik ya da belgelenmis yolla yapilir;
kismen = calisir ama surume bagli, root / ek izin, ya da yalnizca bazi modeller; hayir = iCloud anahtari, sifreli alan ya da Apple'a ozel donanim gerekir.

| Ozellik | Protokol / mekanizma | Uygulanabilirlik | Not | Kaynak |
|---|---|---|---|---|
| Kapak acilinca pil karti (AirPods / Beats) | BLE reklami, Apple uretici kimligi 0x004C, Continuity tipi 0x07 "Proximity Pairing" (27 bayt; model, durum, pil nibble'lari, sarj bitleri, kapak sayaci, renk; son 16 bayt sifreli) | evet (pasif okuma) | Sifreli 16 bayta dokunulmaz; acik alanlar yeterli. Alan anlamlari topluluk arastirmasi, firmware ile degisebilir: kendi cihazla dogrulanacak | [1] [2] [3] |
| Pil seviyeleri (bagliyken, % hassasiyet) | AAP (L2CAP PSM 0x1001) pil bildirimi; Classic tarafta HFP AT+IPHONEACCEV / standart BLE Battery Service (3. parti kulakliklar) | kismen | macOS'ta 3. parti kulakliklar icin IOBluetooth / sistem pil degeri okunabilir; AirPods icin AAP kanali macOS'ta sistem tarafindan zaten tutuluyor olabilir | [4] [5] |
| ANC / seffaf / adaptif mod gecisi (AirPods Pro / Max) | AAP kontrol mesaji (mod baytlari: 01 kapali, 02 ANC, 03 seffaf, 04 adaptif) | macOS: kismen (sistem zaten destekler, uygulama kisayol sunar) / Android: kismen (bazi surumlerde root, L2CAP PSM erisimi) | Mac'te AirPods icin Apple'in kendi denetimi var; uygulama bunu menu cubugu kisayolu olarak sunar. Sony / Bose vb. icin ureticiye ozel GATT/RFCOMM protokolleri ayri is | [4] [6] |
| Kulak algilama (cikarinca durdur) | AAP kulak bildirimi; pasif olarak BLE reklam durum bayti | evet (AirPods) / kismen (3. parti: ureticiye ozel) | Android'de medya oturumunu durdurmak serbest | [4] [6] |
| Otomatik cihaz gecisi (Apple cihazlari arasi) | iCloud Keychain ile paylasilan esleme anahtarlari + Continuity reklamlari + AAP | hayir (taklit) | iCloud anahtarlari ve sifreli durum gerekir; taklit edilmez. Ayni Apple ID'li Apple cihazlarinda zaten var | [5] [7] |
| Otomatik gecis (Mac <-> Android, herhangi kulaklik) | Kendi koordinasyonumuz: Mac'te IOBluetooth baglan / kopar, Android'de BluetoothA2dp/Headset baglanti istegi, iki uygulama arasi yerel ag (Bonjour) ya da BLE ile "ses kimde" mesaji; kulaklik multipoint destekliyorsa daha kolay | kismen | Apple'in ~1 sn hizina ulasilmaz (yeniden baglanti 2-5 sn); Android 12+ baglanti API'leri gizli/sistem izinli olabilir | [8] [9] |
| Cihazlar arasi ses aktarimi (paylasimli dinleme) | Apple: ozel. Standart: LE Audio / Auracast (BT 5.2+ LC3) | kismen | Yalnizca LE Audio destekleyen kulaklik + telefonla; Mac Auracast yayini sunmuyor | [10] |
| Yakinlik algilama (cihaza yaklasinca) | BLE RSSI (kendi cihazlarimizin reklamlari / Android yardimci uygulamanin yaydigi kendi BLE servisimiz) | evet (kaba) | RSSI gurultulu; esik + histerezis. Channel Sounding (BT 6) ileride hassas mesafe | [11] |
| iPhone bildirimlerini Mac'te gormek | ANCS (Apple Notification Center Service), herkese acik BLE GATT spesifikasyonu; Mac "Notification Consumer" olur | evet | iPhone'un esleme onayi gerekir; macOS'ta iPhone Yansitma / bildirim zaten var, Android icin ise yardimci uygulama | [12] |
| Android bildirimlerini Mac'te gormek | Android NotificationListenerService + yerel ag / BLE ile Mac'e iletim (KDE Connect benzeri) | evet | Kendi sifreli kanalimiz (eslestirme kodu), bulut yok | [13] |
| Cagri aktarimi (telefon cagrisini Mac'te acmak) | HFP: Mac "Hands-Free" birim olur, telefon "Audio Gateway"; macOS IOBluetoothHandsFreeDevice | kismen | API eski ve belgelendirmesi zayif; iPhone'la ayni anda iki HFP baglantisi cakisabilir; Android'de HFP AG standart | [14] |
| Evrensel Pano / Handoff | Apple: iCloud + Continuity sifreli mesajlar | hayir (taklit) / evet (kendi kanalimizla pano esleme) | Kendi kanalimizla Mac <-> Android pano paylasimi yapilabilir, Apple Handoff degil | [5] [7] |
| "Bul" (Find My) | iCloud + sifreli donen anahtarlar | hayir | Apple sunucusuna sahte istemci yasak; yalniz son gorulen konum / RSSI'yi yerel kaydetmek mumkun | [7] |
| Spatial audio / bas takibi | AAP icinde jiroskop verisi (AirPods Pro) | kismen / ertelendi | Ilk surumde yok | [4] |

## Kaynaklar

1. furiousMAC, Continuity protokol arastirmasi ve Wireshark dissector, "Proximity Pairing" mesaji: https://github.com/furiousMAC/continuity/blob/master/messages/proximity_pairing.md
2. Martin vd., "Handoff All Your Privacy" (PETS 2019) ve BTLEmap (PETS 2020 demo): https://arxiv.org/pdf/2007.00349
3. ESPHome AirPods ornegi (27 bayt, 07 19 01 oneki): https://git.sudo.is/home-assistant/myhomeiot-esphome-components/src/branch/main/examples/ble_gateway/airpods.yaml
4. LibrePods "AAP Definitions" (AirPods Pro 2 firmware 7A305; GPL, yalnizca okundu): https://git.erfmann.dev/calvin.erfmann/librepods/src/tag/v0.2.0/AAP%20Definitions.md ve https://deepwiki.com/kavishdevar/librepods
5. "Inside Apple AirPods auto-switching" (DEV Community; tek kaynak, dogrulanacak): https://dev.to/lifeart/inside-apple-airpods-auto-switching-bluetooth-continuity-aap-python-packet-sniffing-jf6
6. Gigazine, LibrePods haberi: https://wbgsv0a.gigazine.net/gsc_news/en/20251117-airpods-librepods
7. Celosia ve Cunche, "Discontinued Privacy" (Continuity mesajlari); Heinrich vd., "MagicPairing": https://ar5iv.arxiv.org/html/2005.07255
8. Apple, IOBluetooth (IOBluetoothDevice openConnection / closeConnection) belgeleri: https://developer.apple.com/documentation/iobluetooth
9. Android BluetoothA2dp / BluetoothHeadset / CompanionDeviceManager: https://developer.android.com/reference/android/bluetooth/BluetoothA2dp
10. Bluetooth SIG, LE Audio ve Auracast: https://www.bluetooth.com/auracast/
11. Apple, CoreBluetooth ve Channel Sounding ile mesafe: https://developer.apple.com/documentation/corebluetooth
12. Apple, ANCS spesifikasyonu: https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/
13. Android NotificationListenerService: https://developer.android.com/reference/android/service/notification/NotificationListenerService
14. Apple, IOBluetoothHandsFreeDevice: https://developer.apple.com/documentation/iobluetooth/iobluetoothhandsfreedevice
15. Apple Developer Forums, CoreBluetooth'un PacketLogger'da gorulen servisi gostermemesi: https://developer.apple.com/forums/thread/845352

## Acik dogrulama listesi (kendi cihazlarla)

- macOS 27'de CoreBluetooth taramasi 0x004C / tip 0x07 uretici verisini filtrelemeden veriyor mu? (Forumda filtre izlenimi var [15].) Vermiyorsa yedek: sistemin bildirdigi pil degerleri (IOBluetooth / `system_profiler SPBluetoothDataType`).
- Durum ve sarj baytlarinin bit anlamlari (cevirme / "birincil kulaklik" biti, kulakta bitleri) kendi AirPods'la PacketLogger kaydiyla dogrulanacak; cozucu bunlari "deneysel" isaretler.
- Kaynaklar arasinda celiski: bazi yazilar tipi 0x07 yerine iki baytlik 0x0220 / 0x2220 olarak okuyor (bu aslinda model alani: 0x2002 vb.). Cozucu tip 0x07 + uzunluk 0x19 + onek 0x01 dizisini esas alir.
