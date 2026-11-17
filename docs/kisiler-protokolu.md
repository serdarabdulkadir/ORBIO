# Kisiler ve arama gecmisi senkronu (telefon-kanali.md bolum 7 eki)

Sifreli kanaldan, sayfali. Izinler: `contacts.sync` -> `kisiler`, `calllog.sync` -> `aramaGecmisi` (varsayilan KAPALI; yoksa `error` `izin_yok`). Mac veriyi diske yazmaz; baglanti kopunca ve izin kapaninca bellekten siler.

| `t` | Yon | Alanlar |
|---|---|---|
| `contacts.sync` | mac->tel | `ofset` (kayit sirasi), `adet?` (varsayilan 40, en cok 100) |
| `contacts.page` | tel->mac | `ofset`, `toplam`, `son` (bool), `kisiler`: `[{kid, ad, numaralar:[{no, tur: cep/ev/is/diger}], favori, gruplar:[metin], foto?}]` |
| `contacts.changed` | tel->mac | yok (rehber degisti; Mac bastan ister) |
| `calllog.sync` | mac->tel | `ofset`, `adet?` (varsayilan 100, en cok 200) |
| `calllog.page` | tel->mac | `ofset`, `toplam`, `son`, `kayitlar`: `[{numara, kisiAdi?, yon: gelen/giden/cevapsiz, zaman, sureSn}]` |
| `calllog.changed` | tel->mac | yok |

- `foto`: en cok 96 px JPEG, 8 KB, standart base64. Tek sayfa JSON'u ~450 KB'i gecmez (cerceve siniri 1 MiB); telefon sayfayi kisaltabilir, Mac bir sonraki istegi aldigi kayit sayisindan (`ofset`) yapar. Telefon yalniz `HAS_PHONE_NUMBER=1` olan kisileri gonderir (numarasiz kisiler gonderilmez); `toplam` ve `ofset` bu suzulmus listeye gore sayilir, telefon suzulmus listede satir atlamaz.
- Mac `ofset` degeri tamamlanmis sayi degilse (sira disi sayfa) sayfayi yoksayar; `ofset 0` listeyi sifirlar. Son aranan en cok 300 kayit.
- Test vektorleri: `Tests/EkosistemCoreTests/PeerMessageTests.swift` (`peerKisiSenkronuJSONOrnekleri`) ve Android `PeerMessageTest` ayni dizgileri dogrular.
