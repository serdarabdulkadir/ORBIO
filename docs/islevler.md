# Islev kararlari ve algoritma akisi (2026-11-09)

Kapsam: Mac menu cubugu uygulamasi + Android yardimci uygulama, paralel. Kulakliklar QCY / SoundPEATS / Haylou / Redmi Buds / Soundcore tarzi TWS, AirPods ikincil. Bulut yok, hesap yok. Karar: `docs/karar.md`.

## 1. Islev listesi ve oncelik

Katman A = her modelde calisir (standart Bluetooth). Katman B = model surucusu gerekir (marka GATT / reklam cozumu), yalnizca dogrulanmis modelde acilir.

| # | Islev | Mac | Android | Katman | Oncelik |
|---|---|---|---|---|---|
| 1 | Cihaz listesi, bagli / bagli degil durumu | var | var | A | P0 |
| 2 | Pil (sol / sag / kutu) | panel + kart | ana ekran + bildirim | A (standart pil) / B (kutu, sol-sag ayri) | P0 |
| 3 | Ses kimde: Mac'e bagla / Telefona gonder | var | var | A | P0 |
| 4 | Otomatik gecis (kural bazli) | var | var | A | P1 |
| 5 | Kapak acilinca yaklasma pil karti | var | yok (sistem kendi gosterir) | B (reklam cozumu) | P1 |
| 6 | Ses modu (ANC / Seffaf / Kapali) | segmented | ayni | B | P1 |
| 7 | Kulak algilama (cikarinca duraklat) | var | var | B | P2 |
| 8 | Telefon yakinlik (RSSI) "Yakinda / Uzakta" | var | yayin | A | P2 |
| 9 | Telefon bildirim ve cagri aktarimi Mac'e | alici | gonderen | A | P2 |
| 10 | Mac <-> telefon esleme (6 haneli kod, yerel ag) | var | var | A | P0 |
| 11 | Dusuk pil bildirimi (<= %20, bir kez) | var | var | A | P1 |
| 12 | Ilk kurulum / izinler | var | var | A | P0 |
| 13 | Cihazi unut | var | var | A | P0 |

Disarida: iCloud otomatik gecis, Handoff, Find My, bulut senkron, Windows, "uzaklasinca kilitle". Metrik uydurma yok: bilinmeyen deger "--".

## 2. Karar kurallari (algoritma)

### 2.1 Cihaz durumu
Her cihaz tek durumdan birinde: `bagli_bu_mac`, `bagli_telefon`, `bagli_degil`, `yakinda` (reklam goruluyor, bagli degil), `bilinmiyor`.
- Kaynak onceligi: IOBluetooth baglanti durumu > BLE reklam > son bilinen. Reklam 10 sn gelmezse `yakinda` biter.
- Kayitli cihaz, sinyal yokken `bilinmiyor`; bir sure sonra `bagli_degil`. Pil kaynak onceligi: marka GATT / reklam cozumu > standart Battery Service > yok ("--"). Son guncelleme zamani saklanir; 30 dk'dan eskiyse soluk gosterilir.

### 2.2 Ses gecisi ("Buraya bagla" / "Telefona gonder")
1. Kullanici eylemi veya otomatik kural tetiklenir.
2. Kulaklik multipoint destekliyorsa: ikisine de bagli kal, yalnizca oynatma sahibi degisir. Bitir.
3. Desteklemiyorsa: yerel agdan karsi tarafa `birak` istegi gonder (zaman asimi 3 sn).
   `birak` 3 sn icinde yanitlanmazsa: yalnizca yerel baglanmayi dene (adim 6'daki ipucu ile).
4. Karsi taraf baglantiyi keser, `birakildi` yanitlar.
5. Bu taraf baglanir (zaman asimi 8 sn). Basarisizsa: 1 kez tekrar dene, sonra karsi tarafa `geri al` gonder ve hata goster ("Baglanamadi. Kulakliktaki dugmeye basip tekrar deneyin").
6. Kanal yoksa (esleme yok / ag yok): yalnizca yerel baglan, karsi taraf sahipse kullaniciya "Telefondan ayirin" ipucu goster.

### 2.3 Otomatik gecis kurali (cihaz basina bir secenek)
- `Hicbir zaman` (varsayilan).
- `Telefonda cagri gelince`: telefon `cagri_basladi` yayar -> kulaklik Mac'teyse telefona gecis; cagri bitince 5 sn sonra eski sahibe donus onerisi (otomatik donmez).
- `Medya baslayan cihaza`: bir cihaz medya baslatinca (oturum sinyali) sahiplik ona gecer. Tekrar gecis arasi en az 10 sn (zil-zurna onleme).
- Her otomatik gecis sessiz degil: kisa bildirim + "Geri al" eylemi (30 sn).

### 2.4 Yaklasma pil karti (Mac)
1. BLE tarama arka planda dusuk guc. Taninan cihazdan "kapak acik / yakin" reklam paketi (RSSI > -55 dBm, ust uste 2 paket).
2. Ayni cihaz icin son 60 sn icinde kart gosterildiyse gosterme. Ekran kilitliyse gosterme.
3. Karti goster; 8 sn veya kapak kapaninca kapat. Hareketi azalt acikse yalniz opaklik.
4. Reklam cozulemezse (sifreli / bilinmeyen) kart yerine sistem pil degerine dus; o da yoksa kart gosterme.

### 2.5 Dusuk pil
Sol / sag / kutu ayri izlenir. <= %20 ilk kez gorunce bildirim; %25'in ustune cikmadan tekrar bildirme. Sarjdayken bildirme.

### 2.6 Telefon yakinlik
Telefon yayini RSSI ile filtrelenir (son 5 olcumun ortancasi). Esik: > -70 `Yakinda`, < -85 veya 15 sn yok `Uzakta`. Yalnizca etiket ve istege bagli bildirim; kilitleme yok.

### 2.7 Esleme
1. Mac "Telefonu esle" -> 6 haneli kod uretir (5 dk gecerli, tek kullanim).
2. Telefon Bonjour ile Mac'i bulur, kodu girer; TLS anahtar cifti degisimi.
3. Sonraki baglantilar saklanan anahtarla otomatik. Kod 3 yanlis giriste kilitlenir.

### 2.8 Izinler ve hata durumlari
Bluetooth reddedildi -> panel tek satir ve "Sistem Ayarlari'nda ac". Yerel ag izni yok -> telefon ozellikleri kapali, cihaz ozellikleri calisir. Bildirim izni yok -> kart ve gecis bildirimi yerine panel satiri.

## 3. Ekran envanteri (Figma)

Mac: M1 Menu paneli (dolu / bos, TAMAM) - M2 Yaklasma pil karti - M3 Ayarlar: cihaz detay - M4 Ayarlar: genel + telefon esleme - M5 Ilk kurulum (3 adim) - M6 Durum varyantlari (dusuk pil, sarjda, bagli degil, izin reddedildi, gecis hatasi).
Android: A1 Ana ekran (cihaz listesi + pil) - A2 Cihaz detay (ses modu, kulak algilama, gecis kurali) - A3 Mac ile esleme (kod) - A4 Izin / ilk kurulum - A5 Bildirim ve cagri aktarimi ayarlari.
Akis diyagramlari (FigJam): D1 Ses gecisi - D2 Otomatik gecis - D3 Yaklasma karti - D4 Esleme - D5 Cihaz durumu.

## 4. Cizim sirasi
M2 -> M3 -> M4 -> M5 -> M6 -> A1 -> A2 -> A3 -> A4 -> A5. Her ekran koyu temada, Liquid Glass, ayni bilesenlerle; tek tek, her biri gozle dogrulanir. Android ekranlari Material degil, ayni gorsel dil (kendi cihaz diline uygun sade).

## 5. Kapsam genislemesi (2026-11-09)

### 5.1 Android telefonu bilgisayardan yonetme (Mac, simdilik yalniz Android; Apple cihazlari sonraki faz)
Telefon bilgisayara yerel agda (Bonjour + TLS, 2.7'deki esleme) baglaninca Mac'ten yonetilir. Her yetenek telefonda ayri ayri acilip kapatilir (A6).

| Yetenek | Mac'te ne yapilir | Android mekanigi | Oncelik |
|---|---|---|---|
| Telefon durumu | pil, sarj, ag, ses seviyesi, Rahatsiz Etme | BatteryManager, AudioManager, NotificationManager | P0 |
| Bildirimler | listele, yanitla (hizli yanit), kapat | NotificationListenerService | P0 |
| Kisiler ve yeni arama | rehberde ara, kisiye tikla ve ara, isim / numara yazip yeni arama yap, favoriler, son aranan | READ_CONTACTS (varsayilan kapali), onbellek yok / kisa sureli, yalniz yerel ag | P1 |
| Cagrilar | gelen cagri karti: Yanitla / Reddet / Mesajla reddet; arama yap | InCallService, TelecomManager, ses kulakliga yonlenir | P1 |
| Mesajlar (SMS) | konusmalari oku, yaz, gonder | SMS izni, varsayilan SMS uygulamasi gerekebilir | P1 |
| Telefonu bul | zil cal, konum goster | ses + konum izni | P1 |
| Pano | iki yonlu metin paylasimi (kullanici tetikler) | Android 10+ arka plan pano kisiti: ayrik eylem | P2 |
| Dosya aktarimi | surukle-birak, telefon galerisi / indirilenler | yerel ag, SAF izni | P2 |
| Ekran yansitma ve kontrol | telefon ekrani Mac'te, tikla / yaz | MediaProjection + erisilebilirlik hizmeti; guvenlik agir, acik uyari ve her oturumda onay | P3 |

Karar: dis sunucu yok, veri yalniz yerel agda sifreli. Hassas yetenekler (SMS, cagri, ekran) varsayilan KAPALI, tek tek acilir, her biri ayri izin metniyle.

### 5.2 Android'de kulaklik yonetimi (QCY tarzi + AirPods)
Android uygulamasi yalniz TWS degil Apple kulakliklari da yonetir: AirPods Pro / AirPods / Max (pil sol-sag-kutu, ANC / Seffaf / Uyarlanabilir, kulak algilama, konusma algilama, ad). Mac'teki ayni model destekleriyle ayni ozellik seti. Uygulamada model profili: `Standart` (pil, ses), `TWS surucusu` (marka ozel), `Apple profili`. Apple protokolu kendi cozucumuzle (GPL koddan kopya yok); desteklenmeyen modelde yalniz Katman A gosterilir.

### 5.3 Yeni / degisen ekranlar
Mac: M1'e telefon satiri ("Telefonu yonet"), M7 Telefon penceresi (kenar cubugu: Bildirimler, Mesajlar, Aramalar, Dosyalar, Ekran), M8 Gelen cagri karti, M9 Mesajlar konusmasi, M10 Dosya aktarimi, M11 Ekran yansitma, M3b Ayarlar: AirPods Pro detay (Uyarlanabilir, konusma algilama).
Android: A1'e "Bilgisayar" baglanti karti, A2b AirPods Pro detay, A6 Bagli bilgisayar yonetimi (yetenek bazli izinler), A7 Bildirim / cagri / mesaj aktarimi icin izin akisi.
