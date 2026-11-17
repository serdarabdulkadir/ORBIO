# Telefon tasarimi (Figma'dan cikarilan)

Kaynak: Figma `ZjC4qXHIft7WzjhnjuaNcV`, sayfa "Arsiv" (65:2218). "Ekranlar" sayfasinda (3:19) telefon ekrani YOK (yalniz M1 menu, M2 yaklasma karti, M3 kulaklik ayarlari, M5 ilk kurulum). Telefon ekranlarinin hepsi yalniz KOYU surumde; acik surum yok (belirsiz/eksik).
Not: Figma'daki Android ekranlari da cam/Apple stilinde cizilmis; kullanici karari geregi Android'de yalniz DUZEN + ICERIK alinir, gorsel dil AimTrack paletidir (bkz. 4).

## 1. Ekran / cerceve listesi (Arsiv)

| Kod | Ad | Node id | Boyut |
|---|---|---|---|
| M1 | Menu paneli: Denetim Merkezi (kulaklik; telefon geçisi YOK) | 58:2059 | 440x752 |
| M4 | Ayarlar: genel ve telefon esleme | 33:882 | 640x600 |
| M7 | Telefon penceresi: bildirimler | 52:1416 | 880x700 |
| M8 | Gelen cagri karti | 52:1717 | 640x420 |
| M9 | Mesajlar konusmasi | 54:1455 | 1040x560 |
| M10 | Dosya aktarimi | 54:1712 | 840x620 |
| M11a | Ekran yansitma: telefonda onay bekleniyor | 54:1818 | 920x640 |
| M11b | Ekran yansitma: yansitiliyor | 54:1909 | 920x640 |
| M12 | Aramalar ve kisiler (Yeni arama acik) | 63:2120 | 1040x700 |
| M13 | Cagri sirasinda karti | 63:2297 | 640x488 |
| A1 | Android Ana ekran (Cihazlar) | 56:1601 | 412x892 |
| A2 | Android Cihaz detay (kulaklik) | 56:1821 | 412x892 |
| A2b | Android AirPods Pro detay | 56:1940 | 412x892 |
| A3 | Mac ile esleme | 39:1251 | 412x892 |
| A4 | Izinler ve ilk kurulum | 39:1345 | 412x892 |
| A5 | Bildirim ve cagri aktarimi | 39:1516 | 412x892 |
| A6 | Bagli bilgisayar yonetimi | 56:2048 | 412x892 |
| A7 | Izin akisi: cagrilar | 56:2409 | 412x892 |
| A7b | Izin akisi: ekran paylasimi | 56:2461 | 412x892 |
| A8 | Cagri bilgisayara yonlendirildi | 56:2510 | 412x892 |

Gorulen: 11 Mac + 9 Android telefonla ilgili cerceve (A7b ve A2b ekran goruntusu alinmadi, yalniz ad/yapi). M1b/M6/M3b kulaklik ekranlari kapsam disi. Sahte kisi/numara verileri Figma'da ornek metindir (Ayse Yilmaz, Pixel 8, MacBook Pro); uygulamaya gercek veri baglanir.

## 2. Mac telefon ekranlari

Genel kabuk: tek "Telefon penceresi" (cam, yuvarlak kose, 3 trafik isigi). Sol kenar cubugu: ust baslik cihaz adi ("Pixel 8"), satirlar sirayla `Bildirimler`, `Mesajlar`, `Aramalar`, `Dosyalar`, `Ekran`; bosluktan sonra `Telefon ayarlari` (yalniz M7'de gorunur). Secili satir: acik cam hap. Sag: icerik, ustte bolum basligi.

**M7 Bildirimler** (varsayilan acilis). Ust: telefon karosu (smartphone simgesi, "Pixel 8", alt metin "Bagli, ayni agda", sagda pil simgesi + "64%"). Hap dugmeler: `Telefonu bul`, `Pano gonder`, `Tumunu kapat`. Baslik `Son bildirimler`. Liste satiri: yuvarlak simge (bell.badge / info.circle / clock / lock.shield) + baslik + ozet + sagda saat (09:41). Ilk satirda satir ici `Hizli yanit` alani + `Gonder` hapi. Durumlar: bos/bagli degil Figma'da YOK (belirsiz).

**M8 Gelen cagri karti** (menu cubugu altina acilan 400 pt'lik cam popover). Ust: mavi kare telefon simgesi (smartphone), ad ("Ayse Yilmaz"), alt "Pixel 8 uzerinden gelen arama". Bilgi kutusu (info.circle): baslik "Ses kulakliginiza yonleniyor", alt "QCY T13 ANC bagli. Mikrofon ve ses kulaklikta kalir." Alt satir 3 dugme: `Reddet` (kirmizi), `Mesajla reddet` (notr cam), `Yanitla` (yesil). Kulaklik bagli degilse bilgi kutusunun metni degisir (belirsiz, Figma'da yok).

**M13 Cagri sirasinda** (ayni popover). Ust: harf avatari "A", ad, "02:14, Pixel 8 uzerinden" (sayac monospacedDigit). Kulaklik karosu (earbuds simgesi): "QCY T13 ANC" / "Ses bu kulaklikta". Baslik `Sesi aktar`; 3'lu segment: `Kulaklik` | `Bu Mac` | `Telefon`. Yuvarlak dugmeler (halka, altta etiket): `Sessize al` (bell.badge, sessizde dolu), `Hoparlor` (speaker.wave.2), `Tus takimi` (slider.horizontal.3 yerine SF `circle.grid.3x3` onerilir). Genis kirmizi `Bitir`. Dipnot: "Cagri sesi ve icerigi kaydedilmez, yalnizca yonlendirilir."

**M12 Aramalar ve kisiler.** Baslik `Aramalar`, sag ustte hap `Yeni arama`. Arama alani "Kisi veya numara ara". Segment: `Son aramalar` | `Cevapsiz`. Bolum `Bugun`. Satir: harf avatari (yuvarlak) + ad + alt metin ("Cevapsiz arama", "Gelen arama, 1 dk", "Giden arama, 12 dk", "Gelen arama, 3 dk"); cevapsizlar ad kirmizi. Satirlar ince ayiricli, kart yok. Sag panel `Yeni arama` (300 pt cam popover): baslik, alan (yazinca kisi onerileri: ad + maskeli numara "+90 532 *** ** 12"), 3x4 tus takimi yuvarlak cam tuslar (1-9, `*`, 0, `#`), tam genislik yesil `Ara`. Satira tiklayinca ne olacagi (geri ara?) belirsiz.

**M9 Mesajlar.** 3 sutun: kenar cubugu | konusma listesi (`Mesajlar`; satir: simge avatar, ad, ozet, saat) | konusma (ust: ad + "SMS, telefonunuz uzerinden gonderilir"; baloncuklar gelen sol / giden sag; alt `Mesaj yazin` + `Gonder`). SMS varsayilan KAPALI izinli (A6/A7).

**M10 Dosyalar.** `Dosyalari buraya surukleyin` kesikli cizgili alan, "Telefondaki Indirilenler klasorune gonderilir.", hap `Dosya sec...`. Bolum `Telefon klasorleri`: satirlar `Indirilenler` 128 dosya, `Resimler`, `Belgeler` (sayilar sagda). Bolum `Aktarimlar`: dosya adi, "62%, 2,4 MB/sn", hap `Durdur`, ince ilerleme cubugu (accent); biten satir `Tamamlandi`.

**M11a/b Ekran yansitma.** Sol: telefon cercevesi (220 pt, yuvarlak kose). Sag: uyari kutusu + anahtar listesi + dugme. 11a: kare ici "Telefonda onay bekleniyor" / "Pixel 8 ekraninda Izin ver dugmesine dokunun."; kutu "Telefonda onay gerekir" (kirmizi info); anahtarlar `Mac'ten dokunma ve yazma`, `Telefon sesi` (ikisi kapali); hap `Iptal`. 11b: canli onizleme; kutu "Ekran paylasiliyor" ("Telefondaki her sey bu Mac'te gorunur. Dokunma ve yazma aciksa Mac'ten kontrol edilebilir."); ek satir `Sure 02:14`; kirmizi `Yansitmayi durdur`.

**M4 Ayarlar, "Genel" + telefon esleme.** Sol liste: `Cihazlar` (QCY T13 ANC, QCY HT05, Pixel 8 smartphone simgesiyle), altta `Genel` (gearshape). Genel: anahtarlar `Giriste baslat`, `Menu cubugunda pil yuzdesi`. Bolum `Telefon esleme`: baslik "Telefonda bu kodu girin", 6 hane kutusu (buyuk, monospacedDigit), "Kod 5 dakika gecerli ve tek kullanimlik. Kalan sure 04:32." Satir `Eslenen telefon` / "Pixel 8, yakinda", hap `Yeni kod uret`. Durum: eslenmemis, kod suresi doldu, 3 yanlis deneme kilidi (A3 metni) ekran olarak YOK.

**M1 Denetim Merkezi (440x752, mevcut).** Ustte 2 cihaz karosu (QCY T13 ANC "Bu Mac'e bagli", QCY HT05 "Bagli degil"), `Pil` karosu (halkalar Sol/Sag/Kutu, "Dusuk pil" rozeti), `Ses modu` (Kapali | Gurultu engeli | Seffaf), `Ses` kaydirici, 4 yuvarlak dugme (Kulak algilama, Otomatik gecis, Yakinlik, Sessiz), alt: "Guncel 09:41", `Ayarlar`, `Duzenle`. Telefon bolumu ve ust gecis YOK.

Renk/bosluk (Mac): cam karo koyu yari saydam + 1 pt acik kenar, kose ~16-22; yesil (sistem) Ara/Yanitla, kirmizi Reddet/Bitir/Cevapsiz; accent mavi anahtar ve ilerleme; etiket 11-13 pt, baslik 17 pt yari kalin; satir 40-52 pt. Kontrast olcumu yapilmadi (belirsiz).

Simge esleme (SF Symbols -> Material Symbols): smartphone -> smartphone; iphone.radiowaves -> phone_android + sensors (Telefonu bul: vibration); laptopcomputer -> laptop_mac; earbuds -> earbuds; bell.badge -> notifications_active; info.circle -> info; clock -> schedule; lock.shield -> shield_lock; speaker.wave.2 -> volume_up; folder -> folder; doc.on.clipboard -> content_paste; gearshape -> settings; antenna.radiowaves.left.and.right -> sensors; network -> language; slider.horizontal.3 -> tune; phone.fill (ara/yanitla) -> call; phone.down.fill (bitir) -> call_end; circle.grid.3x3 (tus takimi) -> dialpad; mic.slash (sessize al) -> mic_off.

## 3. Mac paneli: "Kulaklik | Telefon" ust gecisi (Figma'da YOK, oneri)

- Panelin en ustune (cihaz karolarindan once) 320-360 pt genislikte 2'li segment hap: `Kulaklik` | `Telefon`; yukseklik 28 pt, SF `earbuds` ve `smartphone` simgesi + etiket, secili parca acik cam hap (M13'teki `Kulaklik | Bu Mac | Telefon` segmentiyle ayni stil). Secim hatirlanir.
- `Kulaklik` gorunumu = mevcut M1 (degismez).
- `Telefon` gorunumu, ayni cam karo dili:
  1. Telefon karosu (smartphone, ad, "Bagli, ayni agda", pil "64%").
  2. Hap dugme satiri: `Telefonu bul`, `Pano gonder` (M7 ile ayni).
  3. `Son bildirimler` karosu (en cok 3 satir, M7 satiri).
  4. `Aramalar` karosu (en cok 3 son arama + `Yeni arama` hapi; cevapsiz kirmizi).
  5. 4 yuvarlak dugme: `Mesajlar`, `Dosyalar`, `Ekran`, `Ara` (M1'deki yuvarlak dugme stili). Alt: "Guncel 09:41", `Telefon penceresi` hapi (M7'yi acar).
- Bagli degil durumu: karoda "Bagli degil", altta `Telefonu esle` hapi (M4 kodunu acar); bos bildirim/arama metni belirsiz.
- Gelen cagri: panelden bagimsiz M8 karti kendiliginden acilir.
- Menu cubugu simgesi iki moddan hangisi gosterecek: belirsiz (oneri: kulaklik pil yuzdesi kalir, gelen cagri sirasinda telefon simgesine gecer).

## 4. Android uyarlamasi

Palet (AimTrack): koyu zemin #000B18, kart #0B1828, acik zemin #F4F5F7, kose 8/12/18/22. Cam/blur ve Apple tonlari kullanilmaz; kart + ince cizgi. Sistem renkleri (yesil Yanitla, kirmizi Reddet/Bitir) semantik kalir.

- Alt gezinme: `Kulaklik` | `Telefon` (Mac panelindeki ust gecisin karsiligi; Figma'da A1 tek ekran, gecis YOK).
- **Kulaklik ana ekrani** = Mac M1 duzeni: cihaz karolari, Pil (halkalar Sol/Sag/Kutu, "Dusuk pil" rozeti), `Ses modu` (Kapali | Gurultu engeli | Seffaf), `Ses` kaydirici, yuvarlak dugmeler (Kulak algilama, Otomatik gecis, Yakinlik, Sessiz). Figma'daki A1 duzeni (Ses / Kulakliklarim / Bilgisayar / Son durum / Hizli eylemler) ile cakisir; hangisi esas: KARAR GEREKIR (oneri: M1 duzeni, A1'in `Bilgisayar` ve `Hizli eylemler` bolumleri Telefon sekmesine tasinir).
- A2 Cihaz detay: baslik "QCY T13 ANC", "Bu telefona bagli - TWS surucusu"; Pil durumu; Ses modu; Algilama (`Kulak algilama`, `Cikarinca duraklat`); Gecis (`Otomatik gecis kurali` "Telefonda cagri gelince", `Yakinlik bildirimi`); Cihaz bilgisi (`Model`, `Profil`, `Kulakligi bul` + `Bul`); `Buraya bagla`.
- A3 Mac ile esle: "Adim 1/1"; aciklama "Mac'te Ayarlar, Genel bolumunde Telefonu esle secenegini acin. Ekranda gorunen 6 haneli kodu buraya girin."; `Bulunan Mac` satiri (laptop, "Yakinda, ayni agda"); `Esleme kodu` 6 kutu; "Kod 5 dakika gecerli. 3 yanlis denemede kilitlenir."; `Esle`; bilgi "Ayni agda olun".
- A4 Izinler: "Adim 2/3"; `Gerekli izinler`: `Yakindaki cihazlar` (Verildi), `Bildirimler`, `Yerel ag` (`Izin ver`); bilgi "Izinler istege bagli degil"; `Devam`.
- A5 Bildirimler: `Mac'e aktar` (`Cagrilari Mac'te goster`, `Uygulama bildirimleri`, `Aktarilacak uygulamalar` 12); `Uyarilar` (`Dusuk pil, yuzde 20 ve alti`, `Gecis yapilinca bildir`, `Geri al suresi` 30 sn); "Yalnizca yerel ag".
- A6 Bagli bilgisayar: "MacBook Pro / Bagli, ayni agda"; `Varsayilan acik`: Telefon durumu, Bildirimler, Telefonu bul, Dosya aktarimi, Pano; `Hassas, varsayilan kapali`: Cagrilar, Mesajlar (SMS), Ekran yansitma ve kontrol; uyari "Uc yetenek kisisel verinize erisir"; `Eslemeyi kaldir`.
- A7 Cagri izni (Adim 2/4): satirlar Bildirim erisimi / Cagrilar / Mesajlar (SMS) / Ekran paylasimi; kutu "Cagri izni"; `Izin ver`, `Simdi degil`. A7b ayni yapi, ekran paylasimi icin (ekran goruntusu alinmadi, metin belirsiz).
- A8 Cagri bilgisayara yonlendirildi: "Ayse Yilmaz / Gelen cagri"; kutu "Bilgisayara yonlendirildi"; `Cagri`: Su anda yanitlanacak yer, Ses cikisi, Mikrofon; `Telefonda yanitla` (yesil), `Reddet` (kirmizi), `Bilgisayarda birak`.
- Android Telefon sekmesi (Figma'da YOK, A6'dan turetilir): bagli bilgisayar karosu + A6 yetenek anahtarlari ozeti + son durum (pil, ag). Android'de arama GECMISI/tus takimi ekrani Figma'da yok ve gereksiz olabilir (cagri yonetimi Mac'te); belirsiz.

## 5. Figma'da olmayan ama gerekli ekranlar

1. Mac paneli Telefon gorunumu + ust gecis (3'teki tarif) - acik ve koyu.
2. Mac M4 durumlari: eslenmemis, kod suresi doldu, kilitli (3 yanlis deneme), eslesme basarili.
3. Telefon bagli degil / bos durumlari (bildirim, arama, mesaj bos; baglanti koptu).
4. Mac izin/yetki ekrani: telefon cagri/SMS/ekran yetenegi kapali iken ilgili sekmede "Telefonda izin verin" bos durumu.
5. Mac "Mesajla reddet" hazir mesaj secici (M8'de dugme var, secim listesi yok).
6. Arama sirasinda kulaklik bagli degil varyanti (M8/M13).
7. Android bottom nav + Telefon sekmesi + Kulaklik ana ekrani (Mac M1 duzeninde).
8. Android eslesme durumlari: yanlis kod, kod suresi doldu, Mac bulunamadi, kilit.
9. Android izin reddedildi/ayarlara yonlendirme (A4'te yalniz metin var; Cagri/SMS/ekran icin sistem diyalogu oncesi aciklama A7'de var, reddedilmis hali yok).
10. Android acik tema (Figma yalniz koyu).
11. Android A7b ve ekran yansitma onay istegi (telefon tarafi) - A7b mevcut, onaylama ekrani belirsiz.
12. Acik (light) surumler: M4, M7-M13 yalniz koyu.
