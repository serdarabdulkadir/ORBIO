# ORBIO - Logo

## Kavram
Seçilen: **Karşılıklı yaylar** (iki yarım halka + ortada nokta). Sol yay Mac'i, sağ yay telefonu, aralarındaki boşluk devir teslimi, ortadaki nokta de taşınan sesi anlatır.

Elenen kavramlar (`alternatifler/`):
- `b-monogram.svg`: kulaklık kutusu + tek kulaklıktan türeyen B. Daha az sade, küçük boyutta dolgunlaşıyor.
- `bagli-halkalar.svg`: iki bağlı halka. Doğru ama "devir teslim" fikrini taşımıyor, jenerik kalıyor.

## Izgara ve geometri
- 24 birimlik ızgara, merkez (12,12), yarıçap 8, çizgi kalınlığı 2.5, yuvarlak uç.
- Yaylar merkezden +-60 derece (uç noktaları x=8 ve x=16, y=5.07 ve 18.93); orta nokta r=2.
- Wordmark yol (path) olarak çizilmiştir (font yok); büyük harf yüksekliği 12, x-yüksekliği 8, kalınlık 2 (lockup'ta 1.2x ölçekle işaretin kalınlığına eşit).
- Mac ikonu: 1024 tuval, 824 gövde (kenarda 100 px), süperelips n=5, işaret 28x ölçek. Android: 108dp, işaret 2.6x ölçek, 66dp güvenli bölge içinde (`onizleme/android-adaptif-kontrol-1024.png`).

## Renkler
| Rol | Değer |
|---|---|
| Zemin (mürekkep lacivert) | `#0B1828` (ikonda üstte `#112238`'e çok hafif doğrusal geçiş) |
| Vurgu (elektrik mavisi) | `#3478F6` |
| Nötr | `#FFFFFF` (koyu zeminde sol yay ve yazı) |

## Dosyalar
`logo-mark.svg` (açık zemin, şeffaf), `logo-mark-on-dark.svg`, `logo-lockup.svg` (açık zemin), `logo-lockup-on-dark.svg`, `logo-mono-light.svg` (açık zemin, tek renk), `logo-mono-dark.svg` (koyu zemin, tek renk), `app-icon-mac.svg`, `android-icon-foreground.svg` + `android-icon-background.svg`, `favicon.svg`. PNG önizlemeler `onizleme/` altında.

## Kullanım
- Boşluk: işaretin çevresinde en az bir yay kalınlığının 3 katı (7.5 birim); lockup'ta işaret ile yazı arası 6 birim.
- Asgari boyut: işaret 16 px, lockup 96 px genişlik.
- Küçük boyutlarda (favicon) yay kalınlığı 3'e çıkarılmıştır; başka yerde değiştirme.

## Yapılmayacaklar
Yayların yerini/renklerini değiştirme, simetriyi bozma, yay açısını değiştirme; gölge, parıltı, gradyan (ikon zemini dışında), efekt ekleme; standart Bluetooth rünü ya da kulaklık silueti ekleme; mavi dışında vurgu rengi kullanma; wordmark'ı sistem fontuyla yeniden yazma; işareti sıkıştırma/döndürme.
