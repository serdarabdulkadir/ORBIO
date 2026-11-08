# Arayuz tasarimi (Figma oncesi metin tarifi)

Durum: Figma MCP bu oturumda kimlik dogrulamasiz (yalnizca `authenticate` araci mevcut). Figma dosyasi ACILMADI; asagidaki tarif Figma'ya aktarilacak kaynaktir.

## Ilkeler
- macOS yerel dili: SF Pro Text / Display, SF Symbols (monokrom, hiyerarsik), sistem malzemesi yalnizca panel zemininde (`.popover` / `NSVisualEffectView.menu`), ustune ikinci cam katman yok.
- 8 pt izgara; ic bosluk 12 / 16; satir yuksekligi 28 (kompakt) ve 44 (cihaz satiri).
- Tek vurgu rengi: sistem vurgu rengi (`controlAccentColor`), kullanici ne secmisse. Ek renk yalniz anlam icin: dusuk pil (<= %20) `systemRed`, sarj `systemGreen` simsek.
- Isik + karanlik mod sistem renkleriyle (`labelColor`, `secondaryLabelColor`, `separatorColor`, `controlBackgroundColor`); sabit hex yok.
- Metrik uydurma yok: bilinmeyen pil "--" gosterilir, tahmini sure gosterilmez.
- Yazi olculeri: baslik 13 semibold, satir 13 regular, ikincil 11 regular `secondaryLabel`, buyuk pil rakami 22 semibold tabular.

## Ekran 1: Menu cubugu paneli (MenuBarExtra, `.window` stili)
- Genislik 320 pt, yukseklik icerige gore (en cok 480). Kose 10 (sistem).
- Ust: 16 pt kenar bosluk, "Cihazlar" 13 semibold sol; sagda ayarlar dugmesi (`gearshape`, 16 pt, yalniz ikon, ipucu "Ayarlar").
- Bolum 1 "Ses" (aktif ses cikisi): cihaz satiri 44 pt: sol 28x28 SF Symbol (`airpodspro`, `headphones`, `iphone`), ad 13 regular, altinda durum 11 secondary ("Bu Mac'e bagli" / "Telefonda"). Sagda pil grubu: Sol / Sag / Kutu icin 3 kucuk pil gostergesi (16x8 cizgi kutu + yuzde 11 tabular).
- Ses modu secici (yalniz destekleyen kulaklikta): yerel segmented control, 3 ya da 4 segment: "Kapali", "Gurultu engelleme", "Uyarlanabilir", "Seffaf". Yukseklik 24, tam genislik - 32.
- Bolum 2 "Cihazlarim": diger cihaz satirlari (telefon, ikinci kulaklik). Satira tiklayinca "Buraya bagla" / "Telefona gonder" eylemi satir icinde belirir (ikincil dugme, saga yasli). Telefon satirinda telefon pili + "Yakinda" / "Uzakta" (RSSI) etiketi.
- Ayirici: 1 px `separatorColor`, 16 pt iceriden.
- Alt: "Bluetooth Ayarlarini Ac" duz metin dugmesi, 28 pt satir.
- Bos durum: "Henuz cihaz yok. Kulakliginizin kutusunu Mac'in yaninda acin." 13 secondary, ortali, 24 pt ust/alt bosluk.

## Ekran 2: Yaklasma pil karti (kapak acilinca)
- Ekranin alt ortasinda, Dock'un 16 pt ustunde; 360 x 220 pt, kose 18, `NSPanel` (non-activating), sistem malzemesi `.hudWindow` degil `.popover` (sade).
- Ust: cihaz adi 15 semibold ortali, 16 pt ust bosluk; kapat dugmesi sag ust `xmark.circle.fill` 16 pt secondary.
- Orta: 3 sutun (Sol, Sag, Kutu), her biri: urun silueti SF Symbol 48 pt (`airpod.left`, `airpod.right`, `airpodspro.chargingcase`), altinda 22 semibold yuzde, altinda 11 secondary etiket. Sarjdaysa yuzdenin solunda 11 pt `bolt.fill` yesil.
- Alt: tam genislik dugme "Bu Mac'e bagla" (`.borderedProminent`, vurgu rengi, 28 pt), bagliysa "Bagli" pasif etiket.
- Davranis: 8 sn sonra ya da kapak kapaninca kaybolur; ayni cihaz icin 60 sn icinde tekrar cikmaz. Hareket: 200 ms asagidan yukari + opaklik; "Hareketi azalt" aciksa yalniz opaklik.

## Ekran 3: Cihaz detay / ayarlar (ayri pencere, 560 x 420, Settings sahnesi)
- Sol kenar cubugu 180 pt: cihaz listesi + "Genel".
- Sag: Form (`.grouped`): Ad; Pil (Sol / Sag / Kutu, son guncelleme saati); Ses modu; Kulak algilama (ac/kapa, "Cikarinca duraklat"); Otomatik gecis kurali (acilir: "Hicbir zaman", "Telefonda cagri gelince", "Medya baslayan cihaza"); Yakinlik (ac/kapa, "Uzaklasinca kilitle" yok - yalniz bildirim); "Bu cihazi unut" (yikici, kirmizi metin dugme, onayli).
- Genel: Giriste baslat, Menu cubugunda pil yuzdesini goster, Telefon esleme (6 haneli kod).

## Ekran 4: Ilk kurulum / izinler (520 x 400, 3 adim, alt nokta gostergesi yok, "Adim 1/3" metni)
1. Hos geldin: tek cumle ne yaptigi + "Basla".
2. Bluetooth izni: neden gerektigi 2 satir; "Izin ver" (sistem istemini tetikler); durum satiri: Verildi / Bekliyor / Reddedildi (Reddedildiyse "Sistem Ayarlari'nda ac" baglantisi).
3. Bildirimler + giriste baslat (iki onay kutusu) + "Bitti".
- Isteğe bagli 4. adim: "Telefonu esle" (Android yardimci uygulama kurulduysa 6 haneli kod).

## Figma'ya aktarim plani
- Sayfalar: `00 Kapak`, `01 Bilesenler` (cihaz satiri, pil gostergesi, segmented, karti), `02 Ekranlar` (4 ekran x isik / karanlik), `03 Durumlar` (bos, dusuk pil, sarjda, bagli degil, izin reddedildi).
- Degiskenler: renk modlari Light / Dark, sistem renk adlariyla; aralik 4/8/12/16/24.
