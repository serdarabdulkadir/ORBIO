# Telefon kanali sozlesmesi (Mac <-> Android, v1)

Bu belge Swift (Mac) ve Kotlin (Android) tarafinin birebir uygulayacagi tek kaynaktir.
Referans uygulama: `Sources/EkosistemCore/Peer*.swift` (testler: `Tests/EkosistemCoreTests/Peer*Tests.swift`).
Bulut yok: iki cihaz ayni Wi-Fi'de dogrudan konusur. Yalnizca iki platformda yerel primitifler kullanilir.

## 1. Roller ve kesif

- **Mac = sunucu** (`rol: "mac"`): TCP'de dinler ve Bonjour ile yayin yapar. **Telefon = istemci** (`rol: "telefon"`): kesfeder ve baglanir.
- Servis tipi: `_btekosistem._tcp` (Android NSD: `_btekosistem._tcp.`). Port: sistemin verdigi (yayinla birlikte duyurulur).
- TXT kayitlari (hepsi UTF-8 metin): `ad` (cihaz gorunen adi), `surum` (protokol surumu, su an `1`), `id` (kalici cihaz kimligi, rastgele UUID).
- Mac ayni anda tek telefonla oturum tutar (v1). Gelen ikinci baglanti, eslesmis telefon degilse reddedilir.

## 2. Tasima

TCP. Her cerceve: `uzunluk (4 bayt, big-endian, imzasiz) || yuk`. Yuk uzunlugu 1..1 048 576 bayt; 0 veya fazlasi protokol hatasidir, baglanti kapatilir. TCP akisi parcali gelebilir: alici tam cerceve olana dek tamponlar.

- El sikisma cerceveleri (bolum 3) duz JSON'dur.
- El sikismadan sonra her cerceve yuku bolum 5'teki sifreli pakettir.

## 3. El sikisma (duz metin)

Baglanti kurulunca iki taraf da hemen birer `hs` cercevesi gonderir (UTF-8 JSON):

```json
{"t":"hs","v":1,"rol":"mac","pub":"<base64>","nonce":"<base64>","ad":"MacBook"}
```

- `v`: protokol surumu (1). Farkliysa kapat.
- `rol`: `mac` veya `telefon`. Iki taraf ayni rolde ise kapat.
- `pub`: uzun omurlu P-256 acik anahtar, **X9.63 sikistirilmamis nokta, 65 bayt** (`04 || X(32) || Y(32)`), standart base64 (dolgulu).
- `nonce`: 16 rastgele bayt, standart base64.
- `ad`: gorunen ad.
- Alinan `hs` gecersizse (JSON, uzunluklar, gecersiz egri noktasi) kapat.

## 4. Anahtar turetme

Her cihazin kalici bir P-256 kimlik anahtari vardir (Mac: Keychain; Android: Keystore ya da sifreli depo; ham ozel anahtar 32 bayt). Oturum anahtari bu kimlik anahtarlariyla ECDH'dan turetilir (ileri gizlilik yok; nonce'lar her oturumu ayirir).

1. `secret` = ECDH(kendi ozel, karsi acik) -> **32 bayt x koordinati** (CryptoKit `sharedSecretFromKeyAgreement`; Android `KeyAgreement("ECDH").generateSecret()`).
2. `transcript` = `"BTEKO1"` (ASCII, 6 bayt) `|| macPub(65) || telefonPub(65) || macNonce(16) || telefonNonce(16)` (Mac ve telefon sirasi sabit, kimin gonderdigine gore degil role gore).
3. `salt` = SHA-256(`transcript`) (32 bayt).
4. `okm` = HKDF-SHA256(ikm = `secret`, salt = `salt`, info = `"btekosistem/v1"` ASCII, L = 68).
5. Bolme: `okm[0..32)` = mac->telefon AES anahtari; `okm[32..64)` = telefon->mac AES anahtari; `okm[64..68)` = SAS ham degeri.
6. **SAS** = `uint32_big_endian(okm[64..68)) mod 1 000 000`, 6 haneye soldan `0` ile doldurulmus ondalik metin.

Android'de HKDF elle (RFC 5869) yapilir: `PRK = HMAC-SHA256(key=salt, msg=ikm)`; `T(i) = HMAC-SHA256(key=PRK, msg=T(i-1) || info || i)` (i tek bayt, 1'den; T(0) bos); `okm` = T(1)||T(2)||T(3) ilk 68 bayt.

## 5. Sifreli paket

AES-256-GCM. Her yonun kendi anahtari ve sayaci vardir (mac gonderirken `mac->telefon` anahtari, telefon gonderirken `telefon->mac`).

- Gonderen sayac 1'den baslar, her pakette 1 artar (uint64).
- `sayac8` = sayac, 8 bayt big-endian. `nonce` (12 bayt) = `00 00 00 00 || sayac8`. AAD = `sayac8`. Etiket 16 bayt.
- Paket = `sayac8 || sifreliMetin || etiket(16)`; en az 24 bayt. Bu paket cerceve yukudur.
- Alici: once sayaci okur; **sayac <= son kabul edilen sayac ise tekrardir, reddedilir**. Etiket dogrulanirsa son sayaci ilerletir. Dogrulanamayan paket sayaci ilerletmez.
- Etiket dogrulama hatasi, tekrar, kisa paket: **olumcul**, baglanti kapatilir.
- Yazilan acik metin: tek bir JSON mesaji (bolum 7).

## 6. Eslesme (ilk baglanti) ve pin

- Karsi tarafin acik anahtari daha once **sabitlenmemisse** (ilk eslesme): anahtarlar turetilir, iki ekranda ayni 6 haneli SAS gosterilir, kullanici ikisinde de ayni oldugunu onaylar (MITM korumasi: araya giren iki tarafla farkli anahtar kullanacagindan kodlar farkli cikar). Red olursa baglanti kapatilir.
- Onayda: uygulama karsi `pub` degerini kalici saklar (pin: Mac Application Support altinda 0600 dosya [Anahtar Zinciri kullanilmaz], telefon sifreli depo) ve her taraf sifreli `hello` mesajini gonderir. SAS onaylanmadan gelen sifreli mesajlar bekletilir; onaydan sonra islenir, red halinde atilir.
- **Eslesme kodu (istege bagli kapi)**: Mac'te kullanici "Telefonu esle" derse 6 haneli, tek kullanimlik, 5 dk gecerli kod uretilir; aktif kod YOKSA onceki davranis aynen surer (yalniz SAS). Aktif kod varken telefon kodsuz baglanirsa Mac `{"t":"hs_red","neden":"kod_gerekli"}` yollayip kapatir (deneme sayilmaz); telefon kodu sorup `hs` cercevesine `kod` ekler: `base64(HMAC-SHA256(anahtar = kod UTF-8, mesaj = "btrack-pair-v1" || telefon pub || telefon nonce))`. Yanlis kanit (`kod_yanlis`) 3 denemede kodu kilitler (`kilitli`). Kod yalniz ek yetkilendirmedir; SAS karsilastirmasi her durumda surer.
- Anahtar **sabitlenmisse**: `hs.pub` sabitlenen anahtara esit olmali, degilse baglanti kapatilir (kullaniciya "eslesme anahtari degisti" uyarisi; yalniz kullanici eslesmeyi silip yeniden eslestirerek asilabilir). Sabitlenmis anahtarda SAS gosterilmez; oturum dogrudan kurulur. Anahtar sahipligi kanitini, ilk sifreli mesajin dogrulanmasi verir (ozel anahtari olmayan dogru anahtari turetemez).
- Eslemeyi silmek: iki taraf da pini siler.

## 7. Mesajlar

Her mesaj tek JSON nesnesi, UTF-8: `{"t":"<tip>","id":n,...alanlar}`. `id` istege bagli tamsayi; yanit istegin `id` degerini aynen tasir. Bilinmeyen ek alanlar yok sayilir. Eksik zorunlu alan ya da bozuk JSON olumcudur (baglanti kapatilir); bilinmeyen `t` olumcul degildir ve `error` {kod:"bilinmeyen_tip"} ile yanitlanir. Bos (`null`) alanlar yazilmaz, ihmal edilir.

| `t` | Yon | Alanlar |
|---|---|---|
| `hello` | iki yon | `ad`, `surum` (uygulama), `protokol` (1), `cihazId`, `platform` (`mac`/`android`) |
| `ping` / `pong` | iki yon | yok (`pong` yaniti ayni `id`) |
| `phone.state` | tel->mac | `ad`, `model`, `pil` (0-100), `sarj` (bool), `sinyal` (0-4), `ag` (`wifi`/`mobil`/`yok`) |
| `call.state` | tel->mac | `durum`: `bosta`/`caliyor`/`acik`/`araniyor`; `yon`: `gelen`/`giden` (bostayken yok); `numara`, `kisiAdi`, `sureSn` (hepsi opsiyonel) |
| `call.answer` / `call.reject` / `call.hangup` | mac->tel | yok |
| `call.dial` | mac->tel | `numara` |
| `contacts.search` | mac->tel | `sorgu` |
| `contacts.result` | tel->mac | `kisiler`: `[{ad, numaralar:[metin]}]` |
| `calllog.recent` | mac->tel | `adet` (opsiyonel, varsayilan 20) |
| `calllog.result` | tel->mac | `kayitlar`: `[{numara, kisiAdi?, yon: gelen/giden/cevapsiz, zaman (epoch sn), sureSn}]` |
| `earbud.state` | tel->mac | `cihazId`, `ad`, `baglanti`: `telefon` (kulaklik telefona bagli) / `bos` |
| `earbud.release` | mac->tel | `cihazAdresi` |
| `earbud.release.result` | tel->mac | `sonuc`: `tamam`/`desteklenmiyor`/`hata`; `cihazAdresi?` |
| `earbud.connect` | mac->tel | `cihazAdresi` |
| `earbud.connect.result` | tel->mac | `sonuc` (ayni degerler); `cihazAdresi?` |
| `perm.state` | tel->mac | `cagriYonetimi`, `kisiler`, `aramaGecmisi` (bool) |
| `error` | iki yon | `kod`, `mesaj` |

Kurallar:

- Oturum kurulunca iki taraf `hello` gonderir; telefon ardindan `perm.state`, `phone.state` ve varsa `call.state`/`earbud.state` yollar. Durum degisince ilgili `*.state` tekrar gonderilir.
- **Izinler** (telefon tarafi, uygulamada acik anahtarlar, **varsayilan KAPALI**): `cagriYonetimi` -> `call.answer/reject/hangup/dial`; `kisiler` -> `contacts.search`; `aramaGecmisi` -> `calllog.recent`. Mac izin yokken istek gonderse de telefon islemez ve ayni `id` ile `error` {kod:"izin_yok", mesaj:"<izin anahtari>"} doner. Izin degisince `perm.state` yeniden gonderilir. Mac izin kapaliyken ilgili ozellikleri gostermemelidir.
- `earbud.*` istekleri izin gerektirmez (kulaklik gecisi cekirdek ozelligidir).
- Taninmayan `t`: `error` {kod:"bilinmeyen_tip", mesaj:"<t>"}. Diger standart hata kodlari: `izin_yok`, `gecersiz_istek`, `desteklenmiyor`, `mesgul`.
- `ping` en az 15 sn'de bir; 45 sn mesaj gelmezse baglanti olu sayilir, kapatilir, yeniden baglanma telefon tarafindan denenir (ustel geri cekilme, en fazla 30 sn).

## 8. Test vektorleri

Iki platform bu degerleri uretebildigini dogrulamalidir. Hex kucuk harf.

**HKDF (RFC 5869 test 1):** ikm = `0b` x22, salt = `00..0c`, info = `f0..f9`, L=42 ->
`3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865`

**Anahtar turetme (sabit girdiler):**

- mac ozel anahtari (ham 32 bayt): `01 02 .. 20` (1'den 32'ye)
- telefon ozel anahtari: `21 22 .. 40` (33'ten 64'e)
- macNonce: `a0 a1 .. af`; telefonNonce: `b0 b1 .. bf`
- macPub: `04515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354`
- telefonPub: `041f140146bfb1b251f84f4ddbe0d4cdcfd77afd984a9520e35794021f8312bb9eec995a08b1fa7704df3dcc0b50a9665263fb7711f95f9f8a449c5096e47c892b`
- ECDH secret: `4fe243908f378aa1c2a69538822e6ed908c3225d8692575507c649901245150a`
- salt (transcript SHA-256): `ba69f2c2355561d031c3e7fe8c06b0c274daab2afb207059ab9334abd561879a`
- mac->telefon anahtari: `3e7994371738fd367f8393c81893a0371df27a71ed52fdd4142ec49917eccef0`
- telefon->mac anahtari: `cbe20cf9b684bdb2a428ae219e708ce69a45856684940b59a7a0165e3df6aaf8`
- SAS: `538801`

(Not: 1..32 ve 33..64 ham degerleri gecerli P-256 skalerleridir. Android'de ham skalerden anahtar uretmek icin `ECPrivateKeySpec(BigInteger(1, bytes), secp256r1)` kullanin; X9.63 acik anahtari `04 || X || Y` olarak 32 bayta sola sifir doldurarak seri hale getirin.)

**AES-256-GCM:** anahtar = `00 01 .. 1f`, sayac = 1, acik metin = `{"id":1,"t":"ping"}` (UTF-8, 19 bayt) -> paket:
`00000000000000016ef4d69866ce01322c5a7303ced6539972bd6149d15d86aae12692f305fb8fdc1a15c0`
(8 bayt sayac + 19 bayt sifreli metin + 16 bayt etiket.)

**Cerceve:** yuk `01 02 03` -> `00 00 00 03 01 02 03`.

**JSON ornekleri** (alan sirasi onemsiz, referans kodlayici anahtarlari siralar):
`{"id":2,"numara":"555","t":"call.dial"}`, `{"durum":"bosta","t":"call.state"}`,
`{"aramaGecmisi":false,"cagriYonetimi":false,"kisiler":false,"t":"perm.state"}`.

## 9. Uygulama notlari

- Swift: `PeerSession` (durum makinesi: bayt girer, cerceveli bayt ve olay cikar; aga bagli degildir), `PeerCrypto`, `PeerCipher`, `PeerFrameBuffer`, `PeerCodec`. Ag katmani (NWListener/Bonjour) bu cekirdegin dis kabugudur.
- Android: ayni durum makinesini Kotlin'de bire bir yazin; ayni vektorlerle birim testi ekleyin.
- Zaman asimi: el sikisma 10 sn, SAS onayi 60 sn icinde bitmezse kapat.
