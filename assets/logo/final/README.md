# Nihai marka ikonu

Karar: tek ortak ikon = `../apple-tarzi/icon-dark.svg` (koyu lacivert squircle, cam yaylar + nokta).
Tum dosyalar `uret.py` ile kaynaktan uretilir.

## Dosyalar
| Dosya | Platform / kullanim |
|---|---|
| `icon-master.svg`, `icon-master-1024.png` | Ana kaynak; seffaf koseli macOS squircle |
| `AppIcon.iconset/`, `AppIcon.icns` | macOS uygulama simgesi (`scripts/paketle.sh` .app'e kopyalar) |
| `menubar/MenuBarIcon.png`, `@2x.png`, `.svg` | Mac menu cubugu (siyah template, 18pt) |
| `ios-1024.png` | iOS varsayilan: OPAK, kare, alfa yok (iOS maskeyi kendisi uygular) |
| `ios-dark-1024.png`, `ios-tinted-1024.png` | iOS koyu ve tonlu varyantlar (opak) |
| `icon.ico` | Windows: 16, 24, 32, 48, 64, 128, 256 |
| `android-dark-background.svg`, `android-dark-foreground.svg` | Android adaptif katmanlar (108dp, sembol 66dp guvenli bolge icinde) |
| `android/ic_launcher_{foreground,background}_432.png` | Adaptif katman PNG'leri (432 = 108dp @4x) |
| `android/mipmap-*/ic_launcher.png`, `ic_launcher_round.png` | Eski (legacy) launcher simgeleri 48-192 px |
| `favicon.svg`, `favicon-32.png`, `favicon-16.png` | Web |

## Yeniden uretim
`python3 assets/logo/final/uret.py` (gerekir: Brave veya Chrome, Pillow, macOS `iconutil`).
Seffaf PNG, headless tarayici ile `--default-background-color=00000000` kullanilarak alinir.

## Ileride yapilacaklar
- iOS: `ios-*.png` dosyalarini Xcode `AppIcon.appiconset` icine (Any / Dark / Tinted) koy; tonlu varyant gercek cihazda kontrol edilmeli.
- Windows: `icon.ico` uygulama kaynagina ve gerekirse MSIX Square44/150 varlik boyutlarina uyarlanmali.
- Android: mipmap ve adaptif katmanlar `Android/` projesine tasinmadi (baska is akisi); `mipmap-anydpi-v26/ic_launcher.xml` katmanlari bu SVG/PNG'lere baglamali. Monokrom (themed) katman henuz yok.
