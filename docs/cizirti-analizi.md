# QCY cizirti ve durum senkron analizi (2026-11-10)

Durum: kod degisti, DERLENMEDI ve cihazda DENENMEDI. Asagidaki "kok neden" kod okumasindan cikan en guclu hipotezdir; kanit (hava sniffer / A-B denemesi) yok.

## Kok neden (kodda gercekten vardi)

1. Surekli tarama: Mac `BluetoothProvider.centralStateChanged` her acilista `scanForPeripherals(withServices: nil, allowDuplicates: true)` cagirip hic durdurmuyordu. A2DP ile ayni 2.4 GHz bandinda %100 tarama + tekrarli reklam, ses bozulmasinin en olasi nedeni. Android `QcyScanner` SCAN_MODE_LOW_LATENCY ve filtresizdi; ortam hazir oldukca (izinler + Bluetooth acik) surekli calisiyordu.
2. `system_profiler` her ~60 sn (3 sn x 20 tur) calisiyordu; BT denetleyicisini kisa sureli mesgul eder.
3. Yazmalar sirasiz: acilista 6 sorgu + 000D okuma (300 ms arayla ama baska yollardan bagimsiz), her yazimdan sonra geri okuma, telefondan gelen `ctl.write` dogrudan GATT'e; birlesme yok, yeniden deneme (`watchFirstReads`) ek yuk.
4. Geri cekilme sayaci her baglanti kurulunca sifirlaniyordu: kisa omurlu baglanti (iki merkez cakismasi) 5 sn'lik dongu yapabilirdi. Tek-ucus korumasi (`qcyConnecting`) ve sure kontrolu (`qcyNextAttempt`) ZATEN dogruydu.
5. `pollConnections` her 3 sn `IOBluetoothDevice.pairedDevices()` cagiriyordu. AppModel 500 ms dongusu IOBluetooth cagirmiyor (yalniz bellek ici durum), degistirilmedi.
6. Android: `connectGatt` sonrasi baglanti onceligi acikca ayarlanmiyordu; yazmalar `writeLock` ile siralanmisti ama aralik yoktu.
7. Senkron: Mac'te iyimser guncellemenin onay/zaman asimi yoktu; kopunca eski durum gosterilmeye devam ediyordu; cihaz `0x28` (kutuya girme) bildirimine Mac tepki vermiyordu. Android'de yanit hic gelmezse iyimser deger kalici kaliyordu.

## Onlem

- Tarama (Mac, `ScanScheduler`): kontrol kanali hazir ve pil 0008'den geliyorsa KAPALI; kanal yoksa 4 sn acik / 20 sn kapali (yuk %100 -> ~%17); AirPods kayitliysa ayni pencere (yaklasma karti). Tekrarli paket yalniz etkin pencerede. Android: 4/20 (kanal yokken), 2/60 (hazirken), BALANCED + 0x521C uretici verisi filtresi. macOS'ta uretici verisi filtresi yok (yalniz servis UUID); QCY reklaminda servis UUID yok, bu yuzden filtre yapilamadi.
- Pil: Mac GATT 0008'e abone olur ve okur (APK'dan; cihazda dogrulanmadi). Gelmezse seyrek pencere reklam pilini korur. `system_profiler` yalniz BLE pil kaynagi olmayan bagli cihazlar icin ve ~2 dk'da bir; aday yoksa hic calismaz.
- Yazma (Mac, `QcyWriteQueue`): cihaz basina tek sira, en az 200 ms aralik, ayni anahtarli bekleyen istek birlesir, kullanici yazmasi arka plan okumasinin onune gecer, geri okuma 350 ms gecikmeli, yanitsiz yazmada `canSendWriteWithoutResponse` beklenir. Android: `WritePacer` 150 ms ve `CONNECTION_PRIORITY_BALANCED`.
- Yeniden baglanma (`QcyReconnectBackoff`): 5, 10, 20, 30, 60 sn (+%0-20 jitter); sayac yalniz >= 30 sn kararli baglantiyla sifirlanir.
- IOBluetooth: eslesmis cihaz listesi onbellekte (60 sn'de bir yenilenir); 3 sn yoklamada yalniz `isConnected()`.
- Senkron: Mac `QcyOptimisticTracker` (iyimser, 4 sn icinde cihaz onaylamazsa cihazin gercek durumuna doner + uyari; eski bildirim iyimser degeri geri cevirmez). Kopunca durum "bilinmiyor"a doner, baglaninca yeniden okunur; 0x28 gelince mod yeniden okunur; ~90 sn'de bir hafif durum okumasi. Android: yanit yoksa 2.5 sn sonra bir kez daha oku, yine yoksa yazmadan onceki duruma don + hata.
- Mac-telefon paylasimi: mantik ayni (tek sahip). Ek: Mac'te telefon sahipken GATT denenmez (zaten vardi), basarisiz Mac denemeleri en cok 60 sn'ye kadar seyrelir, reklam aktarimi 5 sn'de bir.

## Cihazda dogrulama adimlari

1. `--verbose` ile ac; muzik cal. Log'da "tarama penceresi acik/kapali" yalniz kanal yokken tekrarlanmali; kanal hazirken (kulaklik bagli) pencere gorunmemeli. Cizirti 10+ dk ve ayarlarla oynayarak (ses modu, oyun modu) tekrar uretilmeye calisilsin; once/sonra karsilastirilsin.
2. 0008: log'da pilin geldigi, sol/sag/kutu degerlerinin reklamla ayni oldugu dogrulansin. Gelmiyorsa `gattBattery` bos kalir, seyrek tarama devreye girer (davranis guvenli).
3. Kulakliktaki tusla mod degistir: panel 1 sn icinde guncellenmeli. Kutuya koyup cikar: mod yeniden okunmali.
4. Kulakligi kapatip ac: durum bir an bos ("bilinmiyor"), baglaninca dolmali.
5. Yazma hizi: panelde art arda hizli mod degistir; hava/log'da yazmalar >= 200 ms arayla olmali.
6. Telefon + Mac birlikte: telefonda kontrol ac, Mac "telefon uzerinden" gosterir; geri sahiplik cizirti/duzensiz baglanma olusturmamali.
7. Android: ekran acik, kulaklik bagli; logcat "tarama penceresi acik" aralikli olmali, `BTrack` GATT kopmasi olmamali.

## Dogrulanamayanlar
Derleme/test calistirilmadi. Cizirtinin gercekten tarama yukunden gelip gelmedigi, 0008'in MeloBuds Pro'da notify verip vermedigi, 200 ms araligin yeterli olup olmadigi cihazda gorulmeli.
