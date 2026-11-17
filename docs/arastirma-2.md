# Arastirma 2: AirPods/Android, cagri aktarimi, kisiler, QCY yetenekleri, EQ ve uzamsal ses

Tarih: 2026-11-10. Kapsam: kullanicinin kendi cihazlari. Kod kopyalanmaz; yalniz yontem ogrenilir. "Dogrulanmadi" = bu turda kaynakla teyit edilemedi, kendi cihazda denenmeli.

## 1. Android'de AirPods yonetimi

**Sonuc: yapilabilir, ama root/Xposed kosulu cihaza bagli; HyperOS durumu dogrulanmadi.**

- AAP (Apple Accessory Protocol) L2CAP uzerindedir; ilk belgeleme tyalie'nin Kaitai tanimidir [1]. PSM 0x1001 bilgisi yalniz tek ikincil haber kaynaginda geciyor [3]; tyalie deposu PSM'yi sayfada belirtmiyor (dogrulanmadi, kendi cihazda Wireshark/HCI kaydi ile teyit).
- LibrePods (GPL-3.0) Android'de calisiyor olarak isaretli: dinleme modu degisimi, kulak algilama, pil, ad degistirme, bas hareketleri, konusma algilama (Conversational Awareness), otomatik baglanma. VendorID taklidi (Xposed modulu) gerektirenler: ses azaltma, isitme cihazi, seffaflik ozellestirme, coklu cihaz. Deneysel: kalp atisi, yuksek kaliteli iki yonlu ses. Bilinmeyen: bas takipli uzamsal ses, Find My [2].
- Root: README genel "root sart" demiyor, belirli ozellikler icin "olabilir" diyor [2]. APKMirror surum notlari ve bir ozet, cogu telefonda Android Bluetooth yigininin L2CAP hatasi nedeniyle root/Xposed/modul gerektigini, bazi cihazlarda (ColorOS/OxygenOS 16, guncel Pixel) gerekmedigini soyluyor; kaynak kalitesi dusuk [3][4]. Bir Pixel 7a/Android 16 raporu iki yontemde de "socket created, but not connected" hatasi veriyor [5].
- Xiaomi/Redmi HyperOS: kaynak bulunamadi, **dogrulanmadi**. Test plani: kendi telefonda root'suz L2CAP baglantisi dene; basarisizsa ozellik "gelismis, root" etiketi ile gizli kalsin.
- Kendi kodumuzla: GPL'den kod almadan, tyalie tanimi [1] ve kendi cihazimizin HCI snoop kaydindan paket cozucu yaz (zaten Proximity Pairing cozucumuz ayni felsefe). LibrePods'a yalniz karsilastirma icin bak, kod/yapi kopyalama. Lisans riski: GPL kodunu okuyup birebir cevirmek turev eser sayilabilir; temiz oda (spec belgesi once, kodu baskasi yazar) en guvenlisi.
- Risk: Apple firmware ile protokolu degistirebilir; root/Xposed guvenlik ve garanti riski; Play Store'a uygun degil (dagitim kendi APK'miz). Oncelik: pil (BLE reklamdan, root'suz zaten var) > mod gecisi/kulak algilama (AAP, riskli).
- EQ benzeri: AirPods icin AAP'de kullanici EQ'su belgelenmedi (dogrulanmadi).

## 2. Telefon aramasini Mac'e aktarma

| Yol | Durum | Oneri |
|---|---|---|
| (a) Mac'ten cagri kontrolu (cevapla/reddet/kapat), arayan bilgisi | Yapilabilir | **P1, guvenli** |
| (b1) Arama sesini Mac'e yakalamak (3. parti) | Yapilamaz | Yapma |
| (b2) Telefonu Mac'e HFP gateway yapmak | Guvenilmez | Yapma |
| (b3) Ag uzerinden ses akisi (telefon hoparlor/mikrofon) | Yapilamaz (yakalama yok) | Yapma |
| (c) Kulakligi cagri aninda telefona gecirip bitince Mac'e dondurmek | Yapilabilir | **P1, "bozuk kalmadan" yol** |

- (a): InCallService yalniz varsayilan arama uygulamasi rolu (ROLE_DIALER) ile; bu rol tam arama arayuzu (tus takimi, gelen/giden cagri ekrani, zil bildirimi) gerektirir [6]. Dialer olmayan yardimci uygulama icin InCallService ancak MANAGE_ONGOING_CALLS + CompanionDeviceManager ile fiziksel giyilebilir eslesmesi sartiyla acik [6]; Mac bu kategoriye girmez (dogrulanmadi, deneyerek gor). TelecomManager.acceptRingingCall/endCall API 29'da kullanimdan kalkti, ANSWER_PHONE_CALLS gerektirir; giyilebilir yardimcilari InCallService'e yonlendiriliyor [7]. Pratik: cevapla/reddet icin ANSWER_PHONE_CALLS + TelecomManager (kullanimdan kalkmis ama cihazda calisabilir, dogrulanmadi); gelen arama durumu icin PhoneStateListener/TelephonyCallback (READ_PHONE_STATE). Giden arama baslatma: ACTION_CALL/ TelecomManager.placeCall (CALL_PHONE). Ses Mac'e gelmez, yalniz kontrol + bildirim. KDE Connect telephony eklentisi bu mimarinin kanitidir (arama bildirimi + zili sustur), ses aktarmaz; zili susturma bazi durumlarda titresimi durdurmaz ve zil modunu bozabilir [8]. Bu hatayi tekrarlama: zili susturunca onceki hali geri yukle.
- (b1): VOICE_CALL kaynagi CAPTURE_AUDIO_OUTPUT ister, 3. parti uygulamaya verilmez [9]; Android 10+ root'suz gercek cagri kaydi yok, Play ve erisilebilirlik yolu da kapatildi [9]. Dolayisiyla Android uygulamasi arama sesini yakalayip Mac'e gonderemez.
- (b2): macOS IOBluetooth'ta HandsFree/Gateway siniflari var ama "gelecekte kaldirilabilir" uyarisi, bazi Mac Bluetooth donanimlarinda baslik (headset) destegi yok, HFP 1.6 eksik raporlari (eski topluluk kaynaklari) [10]. Mac'in kulaklik/HF rolunde telefonla kararli calistigina dair kanit bulunamadi: **dogrulanmadi, onerilmez**. Tek denenebilir deney: Mac'i telefona "kulaklik" olarak esleme, sistem ayari, uygulama kodu gerekmez.
- (c) Onerilen akis: Android uygulamasi arama baslayinca (TelephonyCallback RINGING/OFFHOOK) Mac'e "cagri basladi" yollar; kulaklik Mac'e bagliysa "Telefona gonder" kurali (docs/islevler.md 2.2) tetiklenir; cagri bitince (IDLE) "Mac'e don" eski sahibe (veya ayarlanabilir). Multipoint destekli kulaklikta zaten iki cihaza bagli; tel sesi otomatik kulakliga gelir, Mac'te yalniz medyayi durdur. Maliyet: gecis 2-5 sn, ilk zil sesini kacirabilir; bunu "gelen cagri ise once zil kulakliktan duyulmaz" diye kullaniciya soyle.
- **Net oneri:** (a) kontrol+bildirim ve (c) otomatik gecis yapilir; ses aktarimi vaat edilmez. Arayuzde "cagriyi Mac'te konus" secenegi koyma.

## 3. Kisiler ve arama gecmisi

- Android: ContactsContract ile READ_CONTACTS (calisma zamani izni); favoriler (STARRED), arama gecmisi READ_CALL_LOG (CallLog.Calls), fotograf (PHOTO_THUMBNAIL_URI/PHOTO_URI), gruplar (ContactsContract.Groups). Bunlar standart API bilgisidir; bu turda resmi sayfa dogrulamasi yapilmadi (dogrulanmadi).
- Play politikasi: READ_CALL_LOG yalniz varsayilan Telefon/SMS/Asistan isleyicisi olan uygulamalara izinli, aksi halde manifestten cikarilmali [11]. Bu bir kisisel APK (yan yukleme) icin Play kisitini gecersiz kilar; Play'e cikilacaksa risk. 
- Android 14/15'te READ_CONTACTS/READ_CALL_LOG icin yeni ozel kisit bu turda bulunamadi (dogrulanmadi). Bilinen risk: uretici katmanlari (HyperOS) arka plan calisma/otomatik baslatma kisitlar, on plan servisi + pil optimizasyonu muafiyeti gerekir (dogrulanmadi).
- Mac tarafi en iyi pratikler (tasarim onerisi): Android bir kez ozet (ad, numara, kucuk fotograf, yildizli, son aranan) gonderir, sonra degisiklik farki yollar; Mac'te yerel SQLite/SwiftData onbellegi; arama: ad on eki + T9 esleme + numara son 7-10 hane; siralama: favoriler > sik aranan (arama sayisi) > son aranan. Numara normalizasyonu E.164. Aktarim mevcut sifreli kanalimizdan (docs/telefon-kanali.md, AES + ECDH) gecer; kisi verisi diske sifreli (Keychain anahtari) yazilir, kullanici "Kisileri esitleme" aciktan acar, ayrik "unut" duğmesi. Bulut yok.

## 4. QCY / Redmi Buds gizli yetenekleri

Kaynak: topluluk tersine muhendisligi. Quicky (hui1601, Go, 0xFF cerceveli BLE) temel referans, QCYx (Wireshark ile MeloBuds Pro'da dogrulanmis), OpenQCY, oqcy [12][13][14][15]. Cerceve: `FF | govde_uzunlugu | {komut | uzunluk | parametre}...`; komut `0x1001` (yaz), bildirim `0x1002`, pil `0x0008` (3 bayt L,R,kutu; bit7 = sarj), servis `0xA001` (QCYx belgesi) [12][13]. Kulaklik tek istemci kabul eder: resmi uygulama kapali olmali [15]. Model degisince opcode degisebilir.

| Yetenek | Opcode / bilgi | Guvenilirlik |
|---|---|---|
| ANC/seffaf (modern) | `0x17` `[mod, alt, gurultu]` echo + `0x28` sonuc | **Dogrulandi (HT08 kayitlarinda)** [14] |
| Seffaflik | mod `0x03` alt `0x01` (ortam, gurultu bayti = seviye, 0x01/0x03/0x06 gozlendi), alt `0x02` (ses vurgu). Quicky ise `mod 0x0A` alt 1-7 diyor | **5 kademe baytlari belgelenmedi**; iki kaynak celisiyor. Kendi kulakliktan kayit sart |
| ANC derinlik/sahne | QCYx: mod `0x01`, alt 1=ic mekan, 2=gunluk, 3=gurultulu, 4=ruzgar, 5=uyarlanir, gurultu 0-2 = seviye 1-3. Quicky: mod 2/3/4 sahne | Cakisiyor; model/firmware'e gore. Eski `0x0C` HT08'de yoksayiliyor |
| Kulak algilama | `0x06` ac/kapa (01 ac, 02 kapa), `0x2C` takinca durdur/ANC, `0x48` hassasiyet | Dogrulandi (0x2C) |
| Oyun/dusuk gecikme | `0x09 01 01/02` (01 acik, 02 kapali) | Dogrulandi |
| Coklu nokta | Belgelenmedi | Yok |
| Kulaklik bul | Belgelenmedi; `0x05` "light flash" var (ses degil, LED) | Dogrulanmadi |
| Dokunma esleme | Ham karakteristik `0x000D`: `[tus, islev]`; islev 00 yok,01 oynat,02 onceki,03 sonraki,04 asistan,05 ses+,06 ses-,07 oyun,08 cevapla,09 reddet,0A beklet,0B tekrar ara | Quicky belgesi; model basi degisir |
| EQ presetleri | `0x22` MULTIEQ2: 1 bayt preset + 142 bayt tablo, 7 preset | **Dogrulandi (HT08)** [14] |
| 10 bant ozel EQ | `0x20` (v1, 6 bayt/bant) / `0x22` (v2, 7 bayt/bant: frek, kazanc x100 (int16 LE, +-12.7 dB), Q x100, tur); sol/sag `0x46`/`0x47`; slot sayisi `0x44` | Belgeli, cihaz basina sinanmali |
| Codec | Yalniz LDAC `0x23`; AAC secimi yok | Sinirli |
| Ses/denge/limit | `0x08` ses L/R, `0x16` denge (0x32 orta), `0x1D` bildirim sesi | Belgeli |
| Uzamsal ses/bas takibi | `0x2D 01 st` (Quicky "head tracking" der) | Donanim sensor var mi **dogrulanmadi**; MeloBuds Pro/T13'te dogrulanan kayit yok |
| Sensor/ADC verisi | Bulunamadi | Yok |
| Ek | Yan ton `0x0A`, oto kapanma `0x14`, ad `0x18`, LED `0x12/0x35/0x36`, kulak ucu uyum testi `0x11`, ortam uyumu `0x32`, sabit yazilimi guncelleme: **yapma** (bricks riski) | Belgeli |

- T13 ve Redmi Buds 6 bu kaynaklarda dogrulanmis model olarak gecmiyor; QCYx yalniz MeloBuds Pro'yu dogruluyor, Redmi Buds 6 Xiaomi'nin kendi protokolunu (farkli) kullanir, kaynak yok. Yol: kendi telefonda resmi uygulama calisirken Android "Bluetooth HCI snoop log" ac, Wireshark ile cikar, opcode'lari kendi cihazda dogrula (docs/karar.md "pasif kayit" ile uyumlu).

## 5. Tutarli EQ ve uzamsal ses

- En iyi: EQ **kulaklik icinde** (QCY `0x22`/`0x20` ile) yazilir; hangi cihaza baglanirsa baglansin kalir. Her seferinde yazma yerine kullanicinin "profil"ini Mac/Android uygulamasi saklar, bagli olunca yeniden uygular. Cihaz EQ'su yoksa sistem EQ'sine dus.
- Mac: sistem geneli EQ icin Core Audio uzerinde sanal surucu/aggregate cihaz gerekir (AVAudioEngine yalniz kendi uygulamanin sesini isler; sistem sesini islemez). Bu iyi bir ozellik degil, riskli; P2 ve istege bagli. Ayrintili Core Audio dogrulamasi bu turda yapilmadi.
- Android: DynamicsProcessing API 28+ ile kanal basi EQ/limiter sunar, ses oturumuna baglanir [16]; oturum 0 / genel etki durumu bu turda dogrulanmadi (dogrulanmadi). Android 14+ iki genel etkiyi kisitliyor olabilir (dogrulanmadi).
- macOS'ta kafa takibi: CMHeadphoneMotionManager macOS 14+; yalniz Apple'in bas takipli urunlerinden (AirPods Pro/Max/3) hareket verir [17]. 3. parti kulaklikla Apple'in uzamsal ses/baş takibi kullanilamaz. Kendi HRTF kutuphanesini (AVAudioEnvironmentNode) kullanmak mumkun ama bas takibi olmadan sabit; "dogrulanmadi" (3. parti kulaklikta sistem uzamsal sesi acilamadigina dair resmi belge yok). Oneri: uzamsal sesi kapsam disi birak.

## Onerilen uygulama sirasi

| Oncelik | Is | Risk |
|---|---|---|
| P0 | Mac+Android pil, cihaz listesi, esleme, ses gecisi (mevcut plan) | Dusuk |
| P0 | QCY pil, ANC/seffaf/normal (`0x17`, kendi kayitla), game mode `0x09`, kulak algilama `0x06/0x2C` | Orta: model basi dogrulama |
| P1 | Cagri bildirimi + kontrol (Android -> Mac, cevapla/reddet/kapat) | Dusuk-orta (zil modu, rol izinleri) |
| P1 | Cagri aninda kulakligi telefona gecir, bitince don | Orta (2-5 sn gecis) |
| P1 | Kisiler/son aranan/favoriler esitleme + Mac aramasi | Dusuk, gizlilik sifreleme |
| P1 | QCY EQ presetleri `0x22`, dokunma esleme | Orta |
| P2 | Ozel 10 bant EQ (`0x20/0x22`), denge, seviye | Orta |
| P2 | AirPods Android (AAP: mod, kulak algilama) | **Riskli**: root/Xposed, GPL, HyperOS belirsiz |
| P2 | Android DynamicsProcessing EQ | Dusuk-orta |
| Yapma/Ertele | Arama SESI aktarimi, Mac sistem EQ'su (sanal surucu), uzamsal ses/bas takibi, firmware guncelleme | Mumkun degil / yuksek risk |

## Kaynaklar

1. tyalie, AAP protokol tanimi: https://github.com/tyalie/AAP-Protocol-Defintion
2. LibrePods: https://github.com/kavishdevar/librepods
3. ByteIota, LibrePods ozeti: https://byteiota.com/librepods-unlocks-airpods-on-android-lock-in-exposed/ ; APKMirror: https://www.apkmirror.com/apk/kavishdevar/librepods/librepods-0-2-8-release/librepods-0-2-8-android-apk-download/
4. Trendshift (README aynasi): https://trendshift.io/admin/repository/ask-ai/13996
5. LibrePods issue #229 aynasi: https://www.goodfirstissue.org/kavishdevar/librepods/issues/229
6. Android InCallService: https://developer.android.com/reference/android/telecom/InCallService
7. TelecomManager: https://developer.android.com/reference/android/telecom/TelecomManager
8. KDE Connect hata kayitlari: https://bugs.kde.org/show_bug.cgi?id=457778 ; https://bugs.kde.org/show_bug.cgi?id=356147
9. MediaRecorder.AudioSource: https://developer.android.com/reference/android/media/MediaRecorder.AudioSource ; https://github.com/GrapheneOS/os-issue-tracker/issues/3401
10. Apple bluetooth-dev listesi (IOBluetoothHandsFree): https://lists.apple.com/archives/bluetooth-dev/2012/Sep/msg00037.html
11. Google Play SMS/Arama Kaydi politikasi: https://support.google.com/googleplay/android-developer/answer/9047303
12. Quicky protokol: https://github.com/hui1601/Quicky/blob/main/docs/protocol.md
13. QCYx: https://github.com/BrunoAssis/qcyx
14. QCYx paket referansi: https://github.com/BrunoAssis/qcyx/blob/main/docs/protocol/packet-reference.md (ve anc.md)
15. OpenQCY: https://github.com/Matheus-TestUser1/OpenQCY ; oqcy: https://github.com/jean-vr/oqcy
16. DynamicsProcessing: https://developer.android.com/reference/android/media/audiofx/DynamicsProcessing
17. CMHeadphoneMotionManager: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager
