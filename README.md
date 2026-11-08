# BT Ekosistem

Kendi Bluetooth kulakliklarini ve telefonlarini (Apple + Apple disi, karisik) Apple ekosistemindeymis gibi yonetmek icin macOS menu cubugu uygulamasi + istege bagli Android yardimci uygulama.

Durum: arastirma + tasarim + cekirdek iskelet (2026-11-08).

## Dizinler
- `docs/arastirma.md` ozellik / protokol / uygulanabilirlik tablosu ve kaynaklar
- `docs/karar.md` platform karari ve alternatifler
- `docs/tasarim.md` ekran tarifleri ve olculer (Figma'ya aktarilacak)
- `Sources/EkosistemCore` platformdan bagimsiz cekirdek (BLE Proximity Pairing cozucu)
- `Tests/EkosistemCoreTests` birim testleri (Swift Testing)
- `App/` macOS SwiftUI menu cubugu uygulamasi (sonraki tur)
- `Android/` Kotlin yardimci uygulama (ikinci faz)

## Komutlar
```bash
swift build
swift test
```

## Sinirlar
Yalnizca kullanicinin kendi cihazlari ve birlikte calisabilirlik. Sifreli alanlar cozulmez, Apple sunucularina istemci yazilmaz, kimlik taklidi yok. GPL projelerden kod kopyalanmaz; yontem kaynaklari `docs/arastirma.md`'de.
