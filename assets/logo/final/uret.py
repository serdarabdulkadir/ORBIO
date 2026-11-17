#!/usr/bin/env python3
"""BT Ekosistem ortak ikon ciktilarini uretir (kaynak: ../apple-tarzi/icon-dark.svg).

Gereksinim: Brave/Chrome (headless, seffaf PNG), Pillow, macOS iconutil.
Calistirma: python3 assets/logo/final/uret.py
"""
import os, re, subprocess, tempfile, shutil
from PIL import Image, ImageDraw

AD = os.path.dirname(os.path.abspath(__file__))
KAYNAK = os.path.join(AD, "..", "apple-tarzi")
TARAYICI = next(p for p in [
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
] if os.path.exists(p))
tmp = tempfile.mkdtemp()

def oku(ad): return open(os.path.join(KAYNAK, ad), encoding="utf-8").read()
def yaz(yol, s):
    yol = os.path.join(AD, yol); os.makedirs(os.path.dirname(yol), exist_ok=True)
    open(yol, "w", encoding="utf-8").write(s)
def p(yol):
    yol = os.path.join(AD, yol); os.makedirs(os.path.dirname(yol), exist_ok=True); return yol

def render(svg, boyut, cikis):
    """SVG metnini seffaf zeminle boyut x boyut PNG'ye cevirir."""
    html = os.path.join(tmp, "r.html"); png = os.path.join(tmp, "r.png")
    svg = re.sub(r'width="[\d.]+" height="[\d.]+"', f'width="{boyut}" height="{boyut}"', svg, count=1)
    open(html, "w").write(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
    if os.path.exists(png): os.remove(png)
    W = max(boyut, 600)
    subprocess.run([TARAYICI, "--headless", "--disable-gpu", "--hide-scrollbars",
        "--default-background-color=00000000", f"--window-size={W},{W}",
        f"--screenshot={png}", "file://" + html], check=True, capture_output=True)
    im = Image.open(png).convert("RGBA").crop((0, 0, boyut, boyut))
    im.save(cikis); return im

dark = oku("icon-dark.svg")
tinted = oku("icon-tinted.svg")

def parcala(svg):
    defs = re.search(r"<defs>.*?</defs>", svg, re.S).group(0)
    sembol = svg[svg.index('<g filter="url(#sf)">'):svg.rindex("</svg>")]
    return defs, sembol

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {v} {v}" width="{v}" height="{v}">\n'

def ios_svg(kaynak, bg=None):
    defs, sembol = parcala(kaynak)
    if bg:
        defs = defs.replace("#0B1828", bg[0]).replace("#060E19", bg[1])
    k = 1024 / 824  # squircle 824 -> tam kare 1024: sembol orani ayni
    return (HEAD.format(v=1024) + defs +
        '\n<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#sheen)"/>'
        '<rect width="1024" height="1024" fill="url(#vg)"/>\n'
        f'<g transform="translate(512 512) scale({k:.4f}) translate(-512 -512)">\n{sembol}</g>\n</svg>\n')

# --- macOS ---
master = render(dark, 1024, p("icon-master-1024.png"))
shutil.copy(os.path.join(KAYNAK, "icon-dark.svg"), p("icon-master.svg"))
iconset = p("AppIcon.iconset"); shutil.rmtree(iconset, ignore_errors=True); os.makedirs(iconset)
for s in (16, 32, 128, 256, 512):
    master.resize((s, s), Image.LANCZOS).save(f"{iconset}/icon_{s}x{s}.png")
    master.resize((s * 2, s * 2), Image.LANCZOS).save(f"{iconset}/icon_{s}x{s}@2x.png")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", p("AppIcon.icns")], check=True)

# --- iOS (opak, kare) ---
yaz("ios-1024.svg", ios_svg(dark))
yaz("ios-dark-1024.svg", ios_svg(dark, ("#050B14", "#02060B")))
yaz("ios-tinted-1024.svg", ios_svg(tinted))
ios = {}
for ad in ("ios-1024", "ios-dark-1024", "ios-tinted-1024"):
    im = render(open(p(ad + ".svg")).read(), 1024, p(ad + ".png"))
    im.convert("RGB").save(p(ad + ".png")); ios[ad] = im  # alfasiz
    os.remove(p(ad + ".svg"))

# --- Windows ico ---
boyutlar = [16, 24, 32, 48, 64, 128, 256]
master.save(p("icon.ico"), format="ICO", sizes=[(s, s) for s in boyutlar])

# --- Android adaptif (108dp, guvenli bolge 66dp) ---
defs, sembol = parcala(dark)
ANDROID_BG = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="108" height="108">\n'
 '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B1828"/><stop offset="1" stop-color="#060E19"/></linearGradient>'
 '<radialGradient id="vg" cx="54" cy="50" r="68" gradientUnits="userSpaceOnUse"><stop offset="0.6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.45"/></radialGradient>'
 '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.07"/><stop offset="0.45" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>\n'
 '<rect width="108" height="108" fill="url(#bg)"/><rect width="108" height="108" fill="url(#sheen)"/><rect width="108" height="108" fill="url(#vg)"/>\n</svg>\n')
# sembol yaricapi 266 birim -> 32dp icinde (guvenli yaricap 33dp)
ANDROID_FG = (HEAD.format(v=108) + defs +
 f'\n<g transform="translate(54 54) scale(0.12) translate(-512 -512)">\n{sembol}</g>\n</svg>\n')
yaz("android-dark-background.svg", ANDROID_BG)
yaz("android-dark-foreground.svg", ANDROID_FG)
a = "android/"
render(ANDROID_FG, 432, p(a + "ic_launcher_foreground_432.png"))
render(ANDROID_BG, 432, p(a + "ic_launcher_background_432.png"))
govde = master.crop((100, 100, 924, 924))  # eski (legacy) simge: squircle govdesi
daire = Image.new("L", (1024, 1024), 0); ImageDraw.Draw(daire).ellipse((0, 0, 1023, 1023), fill=255)
yuvarlak = ios["ios-1024"].copy(); yuvarlak.putalpha(daire)
for ad, s in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    govde.resize((s, s), Image.LANCZOS).save(p(f"{a}mipmap-{ad}/ic_launcher.png"))
    yuvarlak.resize((s, s), Image.LANCZOS).save(p(f"{a}mipmap-{ad}/ic_launcher_round.png"))

# --- favicon ---
FAV = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">'
 '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B1828"/><stop offset="1" stop-color="#060E19"/></linearGradient></defs>'
 '<rect width="64" height="64" rx="14" fill="url(#g)"/>'
 '<g transform="translate(32 32) scale(0.0719) translate(-512 -512)" fill="none" stroke="#EAF4FF" stroke-linecap="round" stroke-width="96">'
 '<path d="M400 318 A224 224 0 0 0 400 706" stroke-opacity="0.7"/><path d="M624 318 A224 224 0 0 1 624 706"/>'
 '<circle cx="512" cy="512" r="64" fill="#EAF4FF" stroke="none"/></g></svg>\n')
yaz("favicon.svg", FAV)
fav = render(FAV, 256, os.path.join(tmp, "fav.png"))
for s in (32, 16): fav.resize((s, s), Image.LANCZOS).save(p(f"favicon-{s}.png"))

# --- menu cubugu template (siyah, seffaf, 18pt) ---
MB = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18">'
 '<g fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round">'
 '<path d="M5.5 2.94 A7 7 0 0 0 5.5 15.06"/><path d="M12.5 2.94 A7 7 0 0 1 12.5 15.06"/></g>'
 '<circle cx="9" cy="9" r="2" fill="#000"/></svg>\n')
yaz("menubar/MenuBarIcon.svg", MB)
big = render(MB, 144, os.path.join(tmp, "mb.png"))
big.resize((18, 18), Image.LANCZOS).save(p("menubar/MenuBarIcon.png"))
big.resize((36, 36), Image.LANCZOS).save(p("menubar/MenuBarIcon@2x.png"))
shutil.rmtree(tmp)
print("tamam")
