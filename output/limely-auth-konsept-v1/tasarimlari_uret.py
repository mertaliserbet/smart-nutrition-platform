"""Limely mobil kimlik ekranları için yerel, uygulamadan bağımsız tasarım çıktısı."""

import base64
import html
from functools import lru_cache
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
PACK = ROOT / "output/limely-marka-paketi-v1"
BG, INK, MUTED, LIME, SOFT = "#F8FAF2", "#203B2F", "#627365", "#C9E879", "#EAF3DE"
BORDER = "#DFE7DA"


@lru_cache
def font(weight):
    return instantiateVariableFont(
        TTFont(PACK / "fontlar/figtree/figtree.ttf"), {"wght": weight}, inplace=True
    )


def text(value, x, y, size=16, weight=500, color=INK, anchor="start", limit=None):
    face = font(weight)
    cmap, glyphs = face.getBestCmap(), face.getGlyphSet()
    scale = size / face["head"].unitsPerEm
    width = sum(face["hmtx"][cmap[ord(c)]][0] for c in value) * scale
    if limit is not None:
        assert width <= limit, (value, width, limit)
    x -= width / 2 if anchor == "middle" else width if anchor == "end" else 0
    paths = []
    for char in value:
        name = cmap[ord(char)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, y)))
        paths.append(pen.getCommands())
        x += face["hmtx"][name][0] * scale
    return f'<g role="img" aria-label="{html.escape(value, quote=True)}" fill="{color}"><path d="{" ".join(paths)}"/></g>'


def rect(x, y, w, h, radius=20, fill="white", stroke=None, shadow=False):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}"' + (f' stroke="{stroke}"' if stroke else "") + (' filter="url(#soft-shadow)"' if shadow else "") + '/>'


def asset(relative, x, y, w, h=None):
    path = PACK / relative
    mime = "image/svg+xml" if path.suffix == ".svg" else "image/png"
    data = base64.b64encode(path.read_bytes()).decode()
    return f'<image x="{x}" y="{y}" width="{w}" height="{h or w}" href="data:{mime};base64,{data}"/>'


def icon(name, x, y, size=24):
    return asset(f"ikonlar/koyu/{name}.svg", x, y, size)


def custom_icon(name, x, y, size=24):
    shapes = {
        "mail": '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="m4 7 8 6 8-6"/>',
        "lock": '<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/><path d="M12 14v3"/>',
        "eye": '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="2.5"/>',
        "external": '<path d="M14 4h6v6M20 4l-9 9M10 5H6a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-4"/>',
    }
    return f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="0 0 24 24"><g fill="none" stroke="{INK}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{shapes[name]}</g></svg>'


def header(progress=0):
    content = [text("9:41", 24, 24, 13, 600)]
    content += ['<g fill="none" stroke="#203B2F" stroke-width="1.5"><path d="M317 17v-2m4 2v-4m4 4v-6m4 6v-8"/><path d="M337 11q6-6 12 0m-10 3q4-4 8 0m-6 3q2-2 4 0"/><rect x="356" y="9" width="18" height="10" rx="2"/><path d="M377 12v4"/></g><rect x="358" y="11" width="13" height="6" rx="1" fill="#203B2F"/>']
    content += [icon("arrow-left", 23, 69, 25), asset("logolar/limely-yazili-logo-renkli.svg", 116, 48, 158, 57)]
    if progress:
        for i in range(4):
            content += [rect(24 + i * 87, 124, 81, 5, 2.5, LIME if i < progress else SOFT)]
    return "".join(content)


def button(label, y):
    return rect(24, y, 342, 56, 24, LIME) + text(label, 195, y + 35, 19, 800, anchor="middle", limit=310)


def field(label, value, y, symbol, password=False):
    draw_icon = custom_icon if symbol in ("mail", "lock") else icon
    return "".join([
        text(label, 27, y - 12, 14, 650),
        rect(24, y, 342, 56, 18, "white", BORDER),
        draw_icon(symbol, 41, y + 17, 22),
        text(value, 78, y + 35, 16, 450, MUTED, limit=238),
        custom_icon("eye", 326, y + 18, 21) if password else "",
    ])


def wrap(body, title):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="390" height="844" viewBox="0 0 390 844" role="img" aria-label="{title}">
<title>{title}</title><desc>Limely tasarım önerisi; Figtree ve mevcut marka paketi. Çalışan mobil ekran değildir.</desc>
<defs><filter id="soft-shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="5" stdDeviation="8" flood-color="#203B2F" flood-opacity="0.05"/></filter></defs>
{rect(0, 0, 390, 844, 0, BG)}{body}
<rect x="135" y="829" width="120" height="4" rx="2" fill="#203B2F" opacity=".22"/>
</svg>'''


def login():
    return wrap("".join([
        header(),
        asset("dekorlar/maskot-halesi.svg", 114, 116, 162),
        asset("maskotlar/limely-maskot-goz-kirpma.svg", 123, 116, 146),
        text("Yeniden merhaba!", 195, 293, 32, 800, anchor="middle", limit=342),
        text("Küçük adımlarına", 195, 323, 16.5, 450, MUTED, "middle"),
        text("kaldığın yerden devam et.", 195, 346, 16.5, 450, MUTED, "middle"),
        field("E-posta", "ornek@eposta.com", 397, "mail"),
        field("Şifre", "Şifreni gir", 496, "lock", True),
        text("Şifremi unuttum", 363, 579, 14, 650, anchor="end"),
        button("Giriş yap", 608),
        text("Hesabın yok mu?", 181, 704, 15, 450, MUTED, "end"),
        text("Kayıt ol", 192, 704, 15, 750),
        '<path d="M192 708h50" stroke="#203B2F" stroke-width="1"/>',
        '<path d="M68 739H322" stroke="#DFE7DA"/>',
        icon("globe", 93, 762, 19),
        text("Diyetisyen misin?", 122, 777, 14, 650),
        custom_icon("external", 276, 762, 18),
        text("Web paneline geç", 195, 800, 13, 450, MUTED, "middle"),
    ]), "Limely · Giriş yap")


def summary():
    rows = [
        ("sprout", "Hedefin", ["Daha dengeli", "beslenmek"]),
        ("calendar-days", "Yaşın", ["28 yaş"]),
        ("height", "Boyun", ["170 cm"]),
        ("body-scale", "Kilon", ["72,5 kg"]),
        ("walk", "Günlük ritmin", ["Biraz hareketli"]),
    ]
    content = [header(3), rect(24, 160, 342, 147, 28, SOFT)]
    content += [text("Güzel bir", 44, 208, 29, 800), text("başlangıç!", 44, 243, 29, 800)]
    content += [asset("maskotlar/limely-maskot-kutlama.svg", 229, 172, 128)]
    content += [text("Hedefin ve günlük ritmin bir arada.", 27, 339, 16, 450, MUTED, limit=342)]
    content += [rect(24, 365, 342, 283, 24, "white", BORDER, True)]
    for i, (symbol, label, lines) in enumerate(rows):
        y = 365 + i * 56
        content += [icon(symbol, 42, y + 18, 22), text(label, 78, y + 34, 14, 500, MUTED)]
        for j, line in enumerate(lines):
            content += [text(line, 346, y + (26 if len(lines) > 1 else 34) + j * 18, 15, 650, anchor="end")]
        if i < 4:
            content += [f'<path d="M42 {y + 56}H348" stroke="#E9EDE4"/>']
    content += [icon("leaf", 68, 677, 18), text("Küçük adımlar. Sana göre.", 97, 692, 14, 450, MUTED)]
    content += [button("Devam et", 726), text("Şimdi hesabını oluşturalım.", 195, 808, 14, 450, MUTED, "middle")]
    return wrap("".join(content), "Limely · Başlangıç özeti")


def register():
    return wrap("".join([
        header(4),
        asset("maskotlar/limely-maskot-merhaba.svg", 26, 159, 101),
        text("Birlikte", 146, 201, 31, 800),
        text("başlayalım.", 146, 236, 31, 800, limit=220),
        text("Hesabını oluştur, yolculuğun başlasın.", 27, 283, 16, 450, MUTED, limit=342),
        field("Adın soyadın", "Adını ve soyadını gir", 342, "user-round"),
        field("E-posta", "ornek@eposta.com", 431, "mail"),
        field("Şifre", "Şifreni oluştur", 520, "lock", True),
        icon("info", 27, 592, 17),
        text("8–128 karakter kullanabilirsin.", 52, 605, 14, 450, MUTED),
        button("Hesabımı oluştur", 645),
        text("Zaten bir hesabın var mı?", 195, 753, 15, 450, MUTED, "middle"),
        text("Giriş yap", 195, 780, 15, 750, anchor="middle"),
        '<path d="M165 784h60" stroke="#203B2F"/>',
    ]), "Limely · Hesabını oluştur")


if __name__ == "__main__":
    screens = [("01-giris-yap", "Giriş yap", login), ("02-baslangic-ozeti", "Başlangıç özeti", summary), ("03-hesap-olustur", "Hesap oluştur", register)]
    board = [rect(0, 0, 1338, 1138, 0, "#EEF2E8")]
    board += [text("Limely · Giriş ve hesap oluşturma", 36, 63, 31, 800)]
    board += [text("Mevcut marka paketi · Figtree · Mobil ekran tasarım önerisi", 36, 96, 16, 450, MUTED)]
    board += [rect(1124, 33, 178, 34, 17, SOFT), text("TASARIM ÖNERİSİ", 1213, 55, 12, 750, anchor="middle")]
    for i, (name, label, make) in enumerate(screens):
        screen = make()
        (OUT / f"{name}.svg").write_text(screen, encoding="utf8")
        x = 36 + i * 438
        board += [text(label, x + 195, 151, 19, 700, anchor="middle")]
        board += [rect(x, 175, 390, 844, 30, BG, BORDER)]
        board += [f'<defs><clipPath id="phone-{i}"><rect x="{x}" y="175" width="390" height="844" rx="30"/></clipPath></defs>']
        board += [f'<g clip-path="url(#phone-{i})">' + screen.replace('width="390" height="844" viewBox=', f'x="{x}" y="175" width="390" height="844" viewBox=', 1) + '</g>']
    board += [text("Yeni kullanıcı: Karşılama → Hedef → Seni tanıyalım → Özet → Hesap oluştur", 36, 1065, 16, 600)]
    board += [text("Diyetisyen bağlantısı: giriş formunun altında, web paneline geçiş.", 36, 1098, 15, 450, MUTED)]
    for i, color in enumerate([BG, INK, LIME, "#83B977", "#F5D96A", SOFT]):
        board += [rect(1126 + i * 29, 1082, 22, 22, 8, color, BORDER)]
    (OUT / "limely-giris-kayit-konsept-v1.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1338" height="1138" viewBox="0 0 1338 1138">' + ''.join(board) + '</svg>', encoding="utf8")
    print("3 SVG tasarım üretildi; mevcut logo ve maskotlar aynen gömüldü.")
