> **Interoperability research notes, not affiliated with QCY or Apple.** Written to interoperate with earbuds the author owns. Byte meanings carry a confidence level (see below); anything marked [DOGRULANMADI] is unverified and must be treated as experimental. QCY and Apple are trademarks of their owners.

# QCY protokol cozumu (resmi uygulama APK analizi)

Kaynak: QCY resmi uygulamasi `com.qcymall.googleearphonesetup` surum 4.0.7 (yazarin kendi telefonundan yalniz base.apk cekildi, jadx 1.5.6 ile cozuldu). Amac: kullanicinin kendi MeloBuds Pro kulakligi ile birlikte calisabilirlik. Calisma dosyalari depoda yer almaz; APK ve cozulmus kaynaklar dagitilmaz.

Emin olma duzeyleri: **[APK]** = APK kodundan/kaynak dosyasindan okundu, **[APK-JSON]** = APK'daki yerlesik model JSON'undan okundu (baska modelin dosyasi), **[DOGRULANMADI]** = MeloBuds Pro cihazinda denenmedi, **[BULUNAMADI]** = APK'da yok (sunucudan geliyor ya da kodda gorulmedi).

## 1. Tasiyici ve baglanti (kritik)

| Konu | Bulgu | Duzey |
|---|---|---|
| Tasiyici | **BLE GATT** (`QCYHeadsetClient`, inuker BluetoothClient). Klasik RFCOMM/SPP yalniz WuQi (`isWQDevice`, vendorId & 0xF0 == 0x40) yolu icin `BluetoothSPPManager` + UUID `00001101-...` var; genel QCY (V2) yolu BLE. | [APK] |
| GATT servisi | `0000A001-0000-1000-8000-00805f9b34fb` (`QCYHeadsetClient.SERVICE_UUID`). Servis bulunamazsa baglanti "basarili" sayilmaz. | [APK] |
| Baglanti adresi | Resmi uygulama **klasik adrese degil, BLE tarama sonucundaki `scanResult.getDevice().getAddress()` (BLE adresi)** ile baglanir (`isBleMac`, `connectBLE(bleMac)`). Klasik adres (84:AC:60:...) reklam verisinin icinde ayri bir alan olarak tasinir. Sizin `status=147` hatasi buyuk olasilikla klasik adrese GATT acmaya calismaktan geliyor; once reklam taramasi yapip BLE adresini almak gerekir. | [APK] sonuc cikarimi [DOGRULANMADI] |
| Tarama filtresi | `ScanFilter.setManufacturerData(21020 (0x521C), bos)`; ikinci filtre `21036 (0x522C)` veri `47 7E` maske `FF FF` (model 0x477E); ucuncusu Jieli `1494`. Reklam verisi >= 20 bayt olmali. | [APK] |
| Baglanma ayarlari | Retry 3, zaman asimi 10 sn, servis kesfi retry 3 / 20 sn, baglaninca MTU istenir (kullanilan veri boyu = MTU-3, en az 20). Baglaninca `1002` ve notify ozellikli tum karakteristiklere CCCD (notify) acilir. Kulakliga bagli tek istemci olmali (kanit: yok, topluluk bilgisi; kodda bununla ilgili bir kontrol gorulmedi). | [APK] |
| Es zamanli | Telefona klasik (A2DP/HFP) bagliyken BLE GATT ayni anda acilir; kodda klasik baglanti ile BLE baglantisi arasinda bir bagimlilik yok (BLE ayri baglanir). | [APK] |

### 1.1 Reklam verisi (manufacturer data, company ID 0x521C = 21020)

`Devicebind.refreshInfoFromAVData` (veri bayti dizisi `d`, company ID sonrasi):

| Bayt | Anlam |
|---|---|
| d[0], d[1] | **vendorId / model kimligi** = (d[0] << 8) + d[1] (buyuk sonlu) |
| d[3] bit1-3 | renk indeksi `(d[3] & 0x0E) >> 1` |
| d[5], d[6], d[7] | sol, sag, kutu pil: bit7 = sarj oluyor, alt 7 bit = yuzde (1..100 gecerli) |
| d[12],d[11],d[13],d[16],d[15],d[14] | **klasik MAC** (bu sirayla biçimlendirilir: `d12:d11:d13:d16:d15:d14`) |
| d[19],d[18],d[20],d[23],d[22],d[21] | ikinci (diger kulak) MAC; sifirsa klasik MAC ile ayni sayilir |

Yani kulaklik reklam yaparken hem model kimligini hem klasik adresini veriyor. Uygulamanin kulakligi eslestirme mantigi: reklamdan gelen klasik MAC = bagli klasik cihaz, BLE adresi = taramadaki adres. **[APK]**

### 1.2 Karakteristikler (hepsi `0000XXXX-0000-1000-8000-00805f9b34fb`, servis A001)

| UUID | Islev | Yon |
|---|---|---|
| 1001 | komut yazma (FF cerceve, bolum 2) | yaz |
| 1002 | komut cevabi / bildirim (ayni cerceve) | notify/okuma |
| 0008 | pil (3 bayt: sol, sag, kutu; bit7 sarj, alt 7 bit %) | oku/notify |
| 0007 | surum: 6 bayt = sol `a.b.c` + sag `a.b.c` (3 bayt her biri) | oku |
| 000B | eski EQ (10 bant, 1 bayt kademe; bolum 4) | oku/yaz/notify |
| 000D | dokunmatik tus islevi (V2; bolum 3) | oku/yaz |
| 0001..000A | eski (V1) tus karakteristikleri / reset / dil / zaman | modele gore |
| 000C, 000E, 000F | zaman senkronu (V1), ZR ayari, islev bilgisi (V1) | modele gore |

**[APK]** (`ControlerPanl`, `QCYHeadsetClient`). Hangi modelin hangi karakteristikleri sundugu servis kesfinden okunur (`deviceSuportCharacter`); uygulama olmayan karakteristige yazmaz.

## 2. Komut cercevesi (karakteristik 1001 yazma, 1002 cevap)

```
FF | N | { cmdId | len | veri[len] } ...      N = FF sonrasi toplam bayt sayisi (cmdId/len/veri'ler toplami)
```

`DataAnalyse.getSendData`: ilk bayt `0xFF`, ikinci bayt gövde uzunlugu. Cevap ayni cerceve; `cmdId`'ye gore ayristirilir (`DataBean.getDataBean`). Bir cerceve birden cok komut tasiyabilir. **[APK]**

**Sorgu (get):** `FF 03 FE 01 <cmdId>` (cmd 0xFE, uzunluk 1, deger = sorgulanan cmdId). Cevap `FF .. <cmdId> <len> <veri>` seklinde 1002'den gelir. ANC sorgusu icin ayrica `07 01 FF` (deger 0xFF) kullanilir. **[APK]**

**Ayarla (set):** `FF N <cmdId> <len> <veri>`.

### 2.1 Komut ID tablosu (`DataBean.CMDID_*`)

Bu tablo APK sabitlerinden; "set/get" sutunu kodda gorulen kullanimi gosterir. Deger kodlari cogu icin: **1 = ac, 2 = kapat** (0/1 degil).

| cmdId (hex) | Ad (APK) | Set paketi (ornek) | Get / cevap | Not |
|---|---|---|---|---|
| 0x01 | RESET_DEFAULT | `FF 02 01 00` | - | varsayilana don |
| 0x02 | CLEAR_PAIR | `FF 02 02 00` (JSON: `FF020300` "eslesme kayitlarini sil" 0x03 ile) | - | JSON'da `FF020300` "Delete pairing records" |
| 0x03 | FACTORY_RESET | `FF 02 03 00` | - | |
| 0x04 | MUSICACTION | `FF 03 04 01 <a>` a: 1 oynat, 2 kapat, 3 onceki, 4 sonraki | cevap 1 bayt (1 = muzik aktif) | |
| 0x05 | LIGHT | `FF 03 05 01 01/00` (`lightFlash`) | | LED yanip sonme testi; "kulaklik bul" icin kullanimi **BULUNAMADI** |
| 0x06 | RUER (kulak algilama) | `FF 03 06 01 <1 ac / 2 kapat>` | 1 = acik | `RuerDataBean` |
| 0x07 | NOISE | `FF 03 07 01 <deger>` (sorgu: deger 0xFF) | 1 bayt | ANC derinligi/deger; anlami modele ozel |
| 0x08 | VOICE (ses) | `FF 05 08 03 <sol> <sag> 00` | sol, sag, azami (3 bayt) | |
| 0x09 | DIYANSHI (dusuk gecikme = **oyun modu**) | `FF 03 09 01 01` ac, `FF 03 09 01 02` kapat | 1 = acik | JSON `FF03090101` / `FF03090102` ile dogrulandi [APK-JSON] |
| 0x0A | JIANTING | - | - | "dinleme/izleme" olabilir; anlami **BULUNAMADI** |
| 0x0C | NOISEMODE | `FF 03 0C 01 <mod>` | 1 bayt mod | ANC mod kimlikleri modele ozel (bolum 5) |
| 0x0D | TESTMODE | `FF 03 0D 01 <1 ac / 2 kapat>` | | dokunmatik test modu |
| 0x10 | SLEEPMODE | `FF 03 10 01 <1/2>` | | |
| 0x11 | COMPACTNESS (kulak ucu uyum testi) | `FF 04 11 02 <sol 1/2> <sag 1/2>`; "3 deger" bicimi `FF 05 11 03 v v v` | durum, sol sonuc, sag sonuc | |
| 0x12 | LEDMODE | `FF 03 12 01 <1/2>` | | |
| 0x14 | POWERMANAGER (otomatik kapanma) | `FF 06 14 04 <dk_lo> <dk_hi> 00 00` | 4 bayt: ayarli sure, kalan sure (uint16 LE) | birim kodda dakika/saniye belirtilmiyor |
| 0x16 | BALANCE | `FF 03 16 01 <deger>` | 1 bayt | sol/sag denge |
| 0x17 | ANCSETTING | `FF 05 17 03 <mod> <altsahne> <deger>` | 3 bayt: mod, altsahne, deger | yeni ANC (bolum 5) |
| 0x18 | PAIRNAME | `FF N 18 len <UTF-8 ad>` | ad (0 ile biter) | eslesme adi |
| 0x19 | VOICENAME | `FF N 19 len <dil kodu ASCII>` | | ses uyarisi dili (`setVoiceLanger`) |
| 0x1D | TONEVOLUME | `FF 03 1D 01 <deger>` | deger, azami | uyari sesi seviyesi |
| 0x1E | TAKEPHOTO | | | kodda kullanimi gorulmedi |
| 0x1F | STANDBY | | tek deger | |
| 0x20 | MULTIEQ | bolum 4 | `FE 01 20` | 6 baytlik bant |
| 0x22 | MULTIEQ2 | bolum 4 | `FE 01 22` | 7 baytlik bant (+ tur) |
| 0x23 | LDAC | | | kullanim gorulmedi |
| 0x24 | MOREDEVICE (coklu cihaz/nokta) | **BULUNAMADI** (set paketi cozulmedi) | | sabit var |
| 0x27 | AEQ | | | |
| 0x28 | ANC_RESULT | | | |
| 0x29 | ANC_WEAR | | 1 veya 2 bayt (tek bayt ise iki tarafa kopyalanir) | giyme/ANC durumu |
| 0x2B | KEYFUN | bolum 3 | `FE 01 2B` | tus islevi |
| 0x2C | PEIDAI (giyme) | `FF 05 2C 03 <ac> <muzik idx> <anc idx>` (+4. bayt uyari sesi) | 3-4 bayt | |
| 0x2D | SPACE_AUDIO / 0x5B SPACE_AUDIO_MODE | | | uzamsal ses; paket cozulmedi |
| 0x2E | MUSIC_MODE | | | |
| 0x2F | BATTERY | | | (pil asil olarak 0008 karakteristiginden) |
| 0x30 | VERSION | | | surum asil olarak 0007'den |
| 0x32 | ENV_ADAPTATION | | | ortama uyum (ANC) |
| 0x34 | TWS_ENABLE, 0x35 LED_SWITCH, 0x36 LED_EFFECT, 0x37 PLAY_MODE | | tek deger / LED efekt listesi | |
| 0x39 | FOCUS_MODE | | | |
| 0x3A..0x3F | MUSIC_STATE, MUSIC_INFO, TONE_PLAY, SYNC_TIME, ALARM | `SYNC_TIME`: `FF 09 3E 07 <yil%100> <ay> <gun> <saat> <dk> <sn> <haftagunu bit>` | | |
| 0x43 | AI | | | |
| 0x44 | MAXEQ_COUNT | sorgu | tek deger = **azami EQ bant sayisi** | EQ'dan once sorulur |
| 0x45 | CUSTOM_EQ_TEST | | | |
| 0x46 / 0x47 | MULTIEQ_LEFT / RIGHT | bolum 4 | | sol-sag ayri EQ |
| 0x48 | INEAR_SENSITIVITY | | | kulak algilama hassasiyeti |
| 0x4A | GAME_CONFIG | | | |
| 0x4D, 0x4F | PHONE_INFO, PHONE_STATUS | | eslesmis telefon listesi | coklu nokta ile ilgili olabilir |
| 0x50..0x52 | HEAD_ACTION, SENSOR_CONFIG, SENSOR_TEST | `SENSOR_CONFIG` cevabi (tus gibi) cift bayt listesi | | |
| 0x54..0x56, 0x5A | AI_ANC, AI_ANC_CFG, AI_ANC_CFG2, AI_ANC_PREVIEW | | `AIANCSettingDataBean`: durum, gurultu sahnesi, mod, altsahne, deger (+ dokunus idx) | |
| 0x58 | HEAR_HEALTH | | | |

Not: "(set/get) paketi cozulmedi" yazan satirlarda yalniz sabit adi gorulmustur; bayt duzeni icin yeterli kod bulunamadi. **[APK] / ayrintisi [BULUNAMADI]**

## 3. Dokunmatik kontroller

Tus islevleri **model JSON'undan** gelir. Her modelin JSON'u sunucudan indirilir (`WatchHttpAPI.downOneEarphoneNew(vendorId, ...)` -> `data.controlPanel`, tabani `https://api.watch.qcy.com/`); APK'da yalniz uc genel yedek vardir (`controlpan_default.json`, `controlpan_t11.json`, `controlpan_jl.json`). **MeloBuds Pro'nun kendi JSON'u APK'da yoktur; MeloBuds Pro icin tus listesi BULUNAMADI.** Asagisi V2 genel yedeginden okunmustur.

### 3.1 Olay kimlikleri (eventID) [APK-JSON, V1 sabitleri APK]

| eventID | Olay |
|---|---|
| 1 | sol, tek dokunus |
| 2 | sag, tek dokunus |
| 3 | sol, cift dokunus |
| 4 | sag, cift dokunus |
| 5 | sol, uc dokunus |
| 6 | sag, uc dokunus |
| 7 / 8 | sol / sag, dort dokunus (yalniz V1 sabitlerinde, `UUID_KEY_FUNCTION_CL4/CR4`) |
| 9 / 10 | sol / sag, uzun basis (yalniz V1 sabitlerinde `CLL/CRL`) |

Varsayilanlar (`controlpan_default.json`): tek dokunus L/R = 0 (etkisiz); cift dokunus L/R = 1 (oynat/duraklat); uc dokunus L = 7 (oyun modu), R = 4 (sesli asistan). Cagri modunda cift dokunus = yanitla/kapat (islev kodu listesi yok, sabit). `controlpan_t11.json`: yalniz cift (3/4) ve uc (5/6) dokunus; cagri modu tek dokunus.

### 3.2 Islev kodlari (cmd) [APK-JSON, modele gore degisir]

| Kod | Islev |
|---|---|
| 0 | etkisiz |
| 1 | oynat / duraklat |
| 2 | onceki parca |
| 3 | sonraki parca |
| 4 | sesli asistan |
| 5 | ses + |
| 6 | ses - |
| 7 | oyun modu |

ANC mod dongusu, asistan disindaki ek islevler (ANC degistir vb.) icin kodlar bu yedek JSON'larda **yok**; modele ozel JSON'dadir (**BULUNAMADI**).

### 3.3 Yazma / okuma biçimi

- **V2 (genel, `000D` destekleyen modeller):** karakteristik `0000000D` e **[eventID, islevKodu]** ciftleri yazilir (birden cok cift ardarda olabilir): ornek sol cift dokunus -> oynat/duraklat = `03 01`; sag uc dokunus -> sesli asistan = `06 04`. Okuma: `000D` okunur, cevap ayni cift dizisidir (`KeyFuncDataBean`: `[eventID, kod, eventID, kod, ...]`). **[APK]** ([APK] `EarphoneKey`: cmdBytes = `"%02x%02x" (eventID, cmd)`), cihazda **[DOGRULANMADI]**.
- Alternatif yol: 1001 uzerinden cmd 0x2B (`KEYFUN`): `FE 01 2B` sorgusu; cevap ayni cift listesi. Yazma icin ayri paket kodda gorulmedi; yalniz 000D yazisi kullaniliyor.
- **V1 (eski modeller):** her olay icin ayri karakteristik (`0001`..`000A`) ve JSON'daki `cmd` hex dizgisi dogrudan yazilir; JL (Jieli) ve ZR cipli modellerde farkli yol (`JLDeviceImpl.setLeftClick1...`, `ZRDeviceImpl.getKeyFunctionBytes`).
- Model cip ailesi, vendorId'nin alt bayti ile ayrilir (`Devicebind`): `(id & 0xF0) == 0x70` veya `id == 0x200` -> Jieli (RCSP, ayri yol); `0x90` -> ZR; `0x40` -> WuQi (SPP); `0xC0` -> RTK; `(id & 0x80F0) == 0x8070`... yeni Jieli. Diger -> genel V2 (bu belgenin A001/1001 yolu). MeloBuds Pro'nun ailesi vendorId'sinin okunmasiyla (bolum 1.1) belli olur; **APK'da MeloBuds Pro kaydi yok** (bolum 7).

## 4. Ekolayzer

### 4.1 Hazir ayarlar (APK'daki yedek JSON, eski 10 bant sistemi, karakteristik 000B)

Frekanslar (Hz): 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k. Aralik -8..+8 dB (`mindb: 8`, `maxdb: 8`). **[APK-JSON]**

| Indeks (sirayla) | Ad | Bantlar (dB) |
|---|---|---|
| 0 | Default (Varsayilan) | 0,0,0,0,0,0,0,0,0,0 |
| 1 | Pop | -6,5,-3,-2,5,4,-4,-3,6,4 |
| 2 | Bass | 8,7,5,4,0,0,0,0,0,0 |
| 3 | Rock | 7,6,2,1,-3,-4,2,1,4,5 |
| 4 | Soft | 5,-5,-4,-4,3,2,4,4,0,0 |
| 5 | Classic | 6,7,1,2,-1,1,-4,-6,-7,-8 |

Eski yazma (000B): `[eqType] + 10 bayt` (her bant 1 bayt isaretli kademe, dB); okuma 11 bayt: `[eqType, 10 bant]`, 13 bayt ise son iki bayt oyun EQ tipi ve mod. **[APK]**. Modern modellerin (MeloBuds Pro dahil) hazir EQ adlari/indeksleri sunucu JSON'undadir: **BULUNAMADI**.

### 4.2 Ozel EQ (parametrik) paketi, 1001 uzerinden [APK]

Yazma (`setEQWtihQFG2Type`): cmd **0x22** (yeni, 7 bayt/bant) ya da **0x20** (eski, 6 bayt/bant), sol/sag ayri icin **0x46 / 0x47**:

```
FF N <cmd> <len> <eqIndex> <master_lo> <master_hi> { bant }...
 len   = 3 + bantSayisi * (7 | 6)
 master= uint16 LE = master kazanc dB * 100
 bant (0x22): freq_lo freq_hi  gain_lo gain_hi  q_lo q_hi  tur         (7 bayt)
 bant (0x20): freq_lo freq_hi  gain_lo gain_hi  q_lo q_hi              (6 bayt)
 freq = Hz (uint16 LE); gain = int16 LE (dB*100, sinir +-1270 = +-12.7 dB); Q = uint16 LE (Q*100)
 tur  = filtre turu (255 = belirtilmemis); anlamlari kodda adlandirilmamis
```

- Bant sayisi = `min((MTU-7)/6, azamiBant)`; `azamiBant` kulakliktan `FE 01 44` (MAXEQ_COUNT) ile sorulur, bilinmiyorsa 20. Eksik bantlar `freq=0,gain=0,q=0` ile doldurulur; bantlar frekansa gore artan siralanir.
- `eqIndex`: hazir ayar indeksi ya da ozel kayit yuvasi; 255 = ozel/son kullanilan (240 gonderilirken 255'e cevrilir), 128 = kullanilmis ozel yuva, 126 = EQ pazari ayari, 129..239 = ozel kayit kimligi (hazir hex ile `setBytesValue(0x22, ...)`).
- Okuma: `FE 01 20` ve `FE 01 22`; cevap: `[eqIndex, master_lo, master_hi, bant...]` (>9 bayt gecerli); 0x22 cevapta 7 bayt/bant, 0x20'de 6. 0x22 (7 bayt) ile 0x20 (6 bayt) ayrimi: sunucu JSON'undaki `iitType` / model `eqType` listesi doluysa 0x22; vendorId 19779, 19781, 19782, 19783 icin hazir hex 0x20 ile gonderilir.
- 10 bant olan hazir/eski sistem ve parametrik sistem **ayni cihazda** bulunabilir; hangisinin MeloBuds Pro'da kullanildigi cihaz uzerinden **[DOGRULANMADI]**.

## 5. ANC, seffaflik ve diger ayarlar

| Ayar | Opcode ve paket | Deger kodlari | Duzey |
|---|---|---|---|
| ANC modu (eski) | `FF 03 0C 01 <mod>` (set), `FE 01 0C` (get) | mod numaralari **modele ozel** (JSON `modes[].cmdid`, `startcmdid`/`endcmdid`, `voicecmdid`); seviye = `startCMD + secilen seviye - 1` | [APK] mekanizma / degerler [BULUNAMADI] |
| ANC derinligi (eski) | `FF 03 07 01 <deger>` (set), `FF 03 07 01 FF` (oku) | 0..255 modele ozel | [APK] |
| ANC/seffaflik (yeni) | `FF 05 17 03 <mod> <altsahne> <deger>` (set), `FE 01 17` (get) | `mod` 1..3; ozel durum: `(3,1,0)` ise `(3,2,0)` gonderilir (seffaflik/ortam); `altsahne` ve `deger` modele ozel; yuzde seviye kaydirici `deger` = yuzde | [APK] |
| Seffaflik 5 kademe | Ayri bir 5 kademeli bayt tablosu APK'da **yok**; kademe sayisi/sembolleri JSON'da (`ancindex`, `progress`, `valueDescribes`) | - | [BULUNAMADI] |
| AI ANC | cmd 0x54 (durum), 0x55/0x56 (yapilandirma), 0x5A (onizleme) | cevap 5-6 bayt: durum, gurultu sahnesi, mod, altsahne, deger, dokunus idx | [APK] |
| Kulak algilama | `FF 03 06 01 <1 ac / 2 kapat>`; hassasiyet cmd 0x48 | | [APK] |
| Oyun modu (dusuk gecikme) | `FF 03 09 01 01` ac / `FF 03 09 01 02` kapat | | [APK-JSON] |
| Coklu nokta / coklu cihaz | cmd 0x24 (MOREDEVICE), 0x4D/0x4F (telefon bilgisi/durumu) | paketler cozulmedi | [BULUNAMADI] |
| Kulaklik bul | LED: `FF 03 05 01 01/00`; zil sesi komutu gorulmedi (uygulama haritada son konumu gosterir) | | LED [APK], zil [BULUNAMADI] |
| Ses uyarisi seviyesi | `FF 03 1D 01 <deger>` | | [APK] |
| Ses uyarisi dili | `FF N 19 len <dil kodu ASCII>` | metin kodu | [APK] |
| Otomatik kapanma | `FF 06 14 04 <sure_lo> <sure_hi> 00 00` | uint16 LE | [APK], birim [BULUNAMADI] |
| Dil/ad | `FF N 18 len <UTF-8>` (eslesme adi) | | [APK] |
| Giyme / ek | `FF 05 2C 03 <ac 0/1> <muzik idx> <anc idx>` | | [APK] |
| Ses kaydi | **BULUNAMADI** (QCY genel V2 yolunda gorulmedi) | | |
| Zaman senkronu | `FF 09 3E 07 <yil%100> <ay> <gun> <saat> <dk> <sn> <1<<(haftagunu-1)>` | | [APK] |
| Sifirlama | `FF 02 01 00` varsayilan; `FF 02 02 00` / JSON `FF020300` eslesme sil; `FF 02 03 00` fabrika | | [APK], JSON'da `FF020100`/`FF020300` yazili |

ANC mod/seviye sayilari ve adlari (kapali/ANC/seffaflik) model JSON'unda tanimlidir; yedek JSON'larda ANC bolumu yoktur. MeloBuds Pro icin kesin degerler ya cihazdan (1002 bildirimleri izlenerek, `FE 01 17`/`FE 01 0C` sorgulariyla) ya da `api.watch.qcy.com` model yanitindan ogrenilebilir.

## 6. Pil ve surum

| Veri | Nasil | Duzey |
|---|---|---|
| Pil | karakteristik `0008` oku/notify: `[sol, sag, kutu]`, bit7 = sarj, alt 7 bit = yuzde. Reklamdaki pil (bolum 1.1) ayni duzen. | [APK] |
| Surum | `0007` oku: 6 bayt: sol `b0.b1.b2`, sag `b3.b4.b5` | [APK] |
| Surum sorgusu (1001) | `FE 01 30` (VERSION) cmd sabiti var, cevap bicimi kodda ayrintili gorulmedi | [BULUNAMADI] |

## 7. Model kimligi ve modele ozel profil

- Model kimligi = reklam verisindeki `vendorId` (d[0]<<8 | d[1]); sunucuya `downOneEarphoneNew(vendorId, firmwareVersion)` ile gonderilir ve sunucu o modele ait kontrol paneli JSON'unu (tus listesi, ANC modlari, EQ listesi, ayarlar) dondurur. **[APK]**
- APK'nin icindeki `qcy_earphone.json` 33 kayitlik eski model listesidir (T16 0x4B12, T13 0x4A73, T11 0x4DC2, T10 0x4DC1, T5 Pro 0x4D25, T3, T4, T6, T7, T8, T9, T1X, M10, M18 vb.). **MeloBuds Pro bu listede yok**, "MeloBuds" ifadesi APK'da hic gecmiyor; bu surum (4.0.7) bu modeli yerlesik listede tasimiyor, sunucudan aliyor olabilir. MeloBuds Pro vendorId'si bu yuzden **BULUNAMADI**; cihazin kendi reklam verisinden (company 0x521C, ilk iki bayt) okunmalidir.
- vendorId'den cip ailesi: bolum 3.3. Pil dogrulamasi icin ozel liste (`checkBatIDS`), pil gosterimi 10'un katina yuvarlanan modeller icin.

## 8. Uygulamamiz icin sonuc

1. Klasik adrese degil BLE adresine baglan: `CBCentralManager.scanForPeripherals` (Mac) / `BluetoothLeScanner` (Android) ile company ID `0x521C` manufacturer data filtresi; veriden vendorId + klasik MAC al, esle; bagli periferalin BLE adresiyle GATT ac (`status=147` sorununu cozmesi beklenir, **[DOGRULANMADI]**).
2. Servis `A001`; `1002` ve notify ozellikli diger karakteristiklerde CCCD ac; MTU artir.
3. Once `FE 01 44` (azami EQ bant), `FE 01 17`, `FE 01 0C`, `FE 01 20/22`, `FE 01 2B`, pil `0008` ve tus `000D` sorgularini gonderip cevaplari 1002'den kaydet; MeloBuds Pro'nun gercek mod/islev kodlari bu kayitla ogrenilir.
4. Kulaklik tek GATT istemcisi kabul edebilir; resmi uygulama kapali/zorla durdurulmus olmali.
