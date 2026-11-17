# Apple tarzı ikon (Liquid Glass dili)

Kavram mevcut logoyla aynı: iki karşılıklı yay + ortada nokta (24 birimlik ızgara, `../logo-mark.svg`). Yalnızca render dili değişti. Uygulamalara bağlanmadı; mevcut logo dosyalarına dokunulmadı.

## Dosyalar
- `icon-default.svg` mavi zemin (varsayılan), `icon-dark.svg` koyu lacivert zemin, `icon-tinted.svg` gri tonlu (iOS tinted mantığı).
- `android-background.svg` / `android-foreground.svg` adaptif ikon katmanları, 108dp, güvenli bölge 66dp (daire, merkez 54,54).
- `onizleme/` 1024 / 256 / 64 / 32 PNG (üç sürüm) ve `android-birlesik-1024.png` (arka+ön plan, daire maske). PNG'lerde şeffaflık yok, köşeler beyaz (qlmanage çıktısı); gerçek teslimde SVG'den şeffaf dışa aktarın.

## Geometri
- 1024 tuval, squircle (süperelips, n=4.6) 824x824, her kenarda 100 px boşluk.
- Sembol 28 px/birim, çizgi kalınlığı 3 birim, merkez (512,512).

## Işık yönü
Tek kaynak, üstten sol. Üst kenarlar parlak, alt kenarlar hafif koyu; gölge aşağı düşer.

## Katmanlar (alttan üste)
1. Zemin: dikey doğrusal gradyan. Varsayılan #5AA9FF -> #2A6BF2 -> #1747C9. Koyu #0B1828 -> #060E19. Tinted #2E2E30 -> #101011.
2. Üst parlaklık: beyaz %18-20 -> 0 (üst %45), koyuda/tintedde %7-8.
3. Vinyet: kenarlara doğru çok hafif koyulaşma (radyal, %30-45 en uçta).
4. Squircle kenar çizgisi: 3 px beyaz gradyan (üstte %75, altta %28).
5. Sembol (yaylar + nokta): yarı saydam beyaz gradyan (üstte daha opak), sol yay daha saydam, sağ yay ve nokta daha opak (orijinaldeki iki renk ayrımının karşılığı).
   - Filtre: yumuşak kısa gölge (blur 14, dy 16, düşük opaklık), üst kenarda 3 px ince iç ışık, alt kenarda hafif koyu iç çizgi.
   - Speküler: dikey beyaz %30 -> şeffaf geçiş (sembolün üst yarısı).

## Renkler
Mavi aile: #5AA9FF, #2A6BF2, #1747C9. Koyu: #0B1828, #060E19, sembol #EAF4FF -> #9CC6FF. Tinted: #2E2E30, #101011, sembol #FFFFFF -> #D0D0D2.

## Yapılmayacaklar
Parıltı, yıldız, rastgele blur küreleri, mesh gradyan, neon, ikinci renk ailesi, ağır gölge, metin. Efektler yalnızca doğrusal/radyal gradyan ve basit SVG filtresiyle (feGaussianBlur, feOffset, feComposite); feSpecularLighting kullanılmaz.

## Sınırlar
Gerçek macOS Dock / iOS / Android launcher maskesi ve sistemin kendi Liquid Glass işlemesi burada görülmedi; kontrol yalnızca qlmanage (WebKit) çıktısıdır.
