"""Limely önizlemesine özel görsel sınıflandırma ve özgün SVG çizimleri.

Makro sınıflandırması değildir; besin türünü görsel olarak ayırır.
USDA kaynak gruplarını veya besin değerlerini değiştirmez.
"""
import html
import json
from pathlib import Path
from collections import Counter

GROUPS = [
    ('carbs', 'Tahıl ve nişastalılar'), ('proteins', 'Et, balık ve yumurta'),
    ('dairy', 'Süt ürünleri'), ('legumes', 'Baklagiller'),
    ('vegetables', 'Sebze ve yeşillik'), ('fruits', 'Meyveler'),
    ('fats', 'Yağ, kuruyemiş ve tohumlar'), ('drinks', 'İçecekler'),
    ('condiments', 'Sos ve turşular'), ('spices', 'Baharatlar'), ('sweets', 'Tatlı ürünler'),
]

# Each 24 × 24 drawing is authored for this preview; no reference SVG was copied.
DEFINITIONS = [
 ('bread','Ekmek ve tortilla','carbs','wheat','Dilim ekmekler, çok tahıllı ekmekler ve tortilla.',
  '<path d="M5 10C2 8 4 4 8 4h8c4 0 6 4 3 6v9H5Z"/><path d="M8 8h8M8 13v3m4-4v4m4-3v3"/>'),
 ('grains','Pirinç, bulgur ve tahıllar','carbs','wheat','Pirinç, bulgur, kinoa, arpa ve diğer tane tahıllar.',
  '<path d="M12 21V4m0 5c-4 0-6-3-5-6 3 0 5 3 5 6Zm0 5c-4 0-6-2-5-5 3 0 5 2 5 5Zm0 5c-4 0-6-2-5-5 3 0 5 2 5 5Zm0-8c4 0 6-3 5-6-3 0-5 3-5 6Zm0 5c4 0 6-2 5-5-3 0-5 2-5 5Z"/>'),
 ('pasta','Makarna','carbs','wheat','Kuru ve pişmiş makarna, tam tahıllı çeşitler.',
  '<path d="M5 4v6m3-6v6m3-6v5c0 3-6 3-6 0m3 3v9m8-16c-2 1-2 4 0 5s2 4 0 5m4-12c-2 1-2 4 0 5s2 4 0 5"/>'),
 ('flour','Un ve irmik','carbs','wheat','Tahıl, baklagil, kuruyemiş unları ve irmik.',
  '<path d="m7 3 1 4-3 4v9h14v-9l-3-4 1-4ZM8 7h8"/><path d="M12 11v6m0-4-2-1m2 4 2-2"/>'),
 ('oats','Yulaf ve kepek','carbs','wheat','Yulaf ezmesi, çelik kesim yulaf, kepek ve ruşeym.',
  '<path d="M3 12h18c-1 6-4 8-9 8s-8-2-9-8Zm3 9h12M16 10l4-7"/><path d="m6 9 2-2 2 2m1-1 2-2 2 2"/>'),
 ('tubers','Patates ve nişastalı kökler','carbs','wheat','Patates ve tatlı patates; havuç ve pancar bu grupta değildir.',
  '<path d="M19 7c4 4 0 11-6 13-5 2-10-2-9-6 0-4 5-9 9-10 2-1 5 0 6 3Z"/><path d="m8 12 1 1m3-5 1 1m2 6 1 1m-6 1h.1"/>'),
 ('poultry','Tavuk ve hindi','proteins','rose','Göğüs, but, kanat ve kümes hayvanı kıymaları.',
  '<path d="M12 6c3-3 8-1 8 3 0 4-4 7-7 6L8 19l-3-3 4-5c-1-2 0-4 3-5Z"/><path d="m6 17-2 2m1-1c-2-2-4 1-2 2s4 0 3-2"/><path d="m14 8 2 1"/>'),
 ('red-meat','Kırmızı et ve kıyma','proteins','rose','Dana ve kuzu eti; pişirme durumu ayrıca korunur.',
  '<path d="M4 9c2-5 8-6 12-3 5 3 6 10 2 13s-6-1-10-1c-5 0-6-4-4-9Z"/><path d="M7 10c2-3 5-3 7-1s5 5 2 7-4-2-7-1c-3 0-4-2-2-5Z"/><circle cx="17" cy="9" r="1"/>'),
 ('fish','Balık','proteins','blue','Somon, ton balığı, hamsi, uskumru ve diğer balıklar.',
  '<path d="M4 12c4-7 11-7 15 0-4 7-11 7-15 0Zm0 0-2-4v8Zm7-6 3-3 2 4m-5 11 3 3 2-4"/><path d="M15 9c-2 2-2 4 0 6"/><circle cx="17" cy="11" r=".7" fill="currentColor" stroke="none"/>'),
 ('seafood','Deniz ürünleri','proteins','blue','Karides ve kalamar gibi balık dışı deniz ürünleri.',
  '<path d="M19 7c-2-4-8-4-11-1-4 4-2 10 3 11 3 1 6-1 6-4 0-2-2-3-4-2m6-4 3-2m-4 3 4 1M8 8l4 3m-6 1 5 1m-4 3 5-1m0 2 1 4 3-3"/><circle cx="17" cy="7" r=".6" fill="currentColor" stroke="none"/>'),
 ('eggs','Yumurta','proteins','sand','Bütün yumurta, ak, sarı ve kurutulmuş yumurta ürünleri.',
  '<path d="M19 14c0 5-3 7-7 7s-7-2-7-7S9 3 12 3s7 6 7 11Z"/><path d="M8 14c0 2 1 4 3 4"/>'),
 ('cheese','Peynir','dairy','sand','Feta, cheddar, mozzarella, cottage ve diğer peynirler.',
  '<path d="m3 10 10-6 8 5v11H3Z"/><path d="M3 10h18M13 4c-1 3 2 5 8 5"/><circle cx="8" cy="14" r="1.1"/><circle cx="16" cy="16" r="1.5"/><path d="M3 17c3-1 4 2 2 3"/>'),
 ('yogurt','Yoğurt','dairy','sand','Sade, süzme tipi ve aromalı yoğurtlar.',
  '<path d="M5 8h14l-2 13H7ZM4 5h16v3H4Z"/><path d="M9 13c1-3 5-3 6 0m-6 3h6M10 3h4"/>'),
 ('milk','Süt','dairy','sand','İnek sütü ve kültürlü süt. Bitkisel içecekler ayrı gruptadır.',
  '<path d="M8 3h7l3 5v13H6V8Zm0 0v5h10M6 8l4-5m2 10c-4 4-4 6 0 6s4-2 0-6Z"/>'),
 ('cream','Krema','dairy','sand','Süt kreması ve ekşi krema; krem peynir peynir grubundadır.',
  '<path d="M4 13h16c-1 5-3 7-8 7s-7-2-8-7Zm3-2c-2-2 1-4 4-4-1-2 0-3 2-4 0 3 5 3 4 6 3 0 3 2 1 2Z"/>'),
 ('legumes','Baklagiller','legumes','sage','Kuru ve pişmiş nohut, mercimek, fasulye, börülce; humus.',
  '<path d="M4 14C2 7 8 3 15 4c7 1 6 10 1 10-3 0-1 5-6 6-3 0-5-2-6-6Z"/><path d="M8 8c-2 2-2 6 1 8m2-8c3-1 6 0 6 2"/>'),
 ('vegetables','Sebzeler','vegetables','sage','Domates, biber, havuç, kabak ve benzeri sebzeler.',
  '<path d="M15 7c4 3-5 12-11 14C6 15 10 5 15 7Zm-1-1 1-4m1 5 5-3m-6 3 5 2M9 12l2 2m1-5 2 2"/>'),
 ('leafy-greens','Yapraklılar ve taze otlar','vegetables','sage','Marul, ıspanak, lahana, roka ve taze aromatik otlar.',
  '<path d="M19 3C8 2 3 6 4 13c0 6 6 8 10 5 5-3 6-8 5-15ZM5 21 16 7m-6 6-3-1m6-2 1-3m-1 7 4-1"/>'),
 ('mushrooms','Mantarlar','vegetables','sage','Kültür, istiridye, şitake ve diğer mantarlar.',
  '<path d="M3 12c0-6 4-9 9-9s9 3 9 9H3Zm6 0-1 8h8l-1-8"/><path d="M7 8h.1M12 6h.1M17 9h.1M10 16h4"/>'),
 ('fresh-fruit','Meyveler','fruits','peach','Taze, şekersiz dondurulmuş meyve, sade meyve püresi ve avokado.',
  '<path d="M12 7c-4-4-9-1-9 4 0 4 4 10 7 10l2-1 2 1c3 0 7-6 7-10 0-5-5-8-9-4Zm0 0V3m1 2c3 0 5-1 5-3-3-1-5 0-5 3Z"/>'),
 ('dried-fruit','Kuru meyve','fruits','peach','Kuru incir, kayısı, hurma, kuru üzüm ve kuru erik.',
  '<path d="M8 4c3-2 6 1 5 5s-2 9-5 11c-3 2-6-1-5-5S5 6 8 4Zm8 4c3-2 6 1 5 5s-2 7-5 8c-3 1-5-2-4-5"/><path d="m8 7-2 8m11-3-2 5"/>'),
 ('oils','Yağ ve tereyağı','fats','olive','Bitkisel yağlar, tereyağı ve susuz süt yağı.',
  '<path d="M10 3h5v4l3 4v10H6V11l4-4Zm0 4h5M6 12h12m-6 2c-3 3-3 5 0 5s3-2 0-5Z"/>'),
 ('nuts','Kuruyemiş','fats','olive','Ceviz, badem, fındık, Antep fıstığı, kaju ve kestane.',
  '<path d="M11 3c5 3 8 8 8 12 0 8-14 8-14 0 0-4 3-9 6-12Z"/><path d="M11 7c-3 6-3 9-1 12m3-11c3 5 3 8 1 11"/>'),
 ('seeds','Tohum ve çekirdek','fats','olive','Susam, keten, chia, ay çekirdeği ve kabak çekirdeği.',
  '<path d="M8 3C3 8 3 13 7 14s7-4 1-11Zm10 7c-7 3-10 7-7 10s8 1 7-10Z"/><path d="m8 7-1 4m9 3-3 4"/>'),
 ('spreads','Tahin ve kuruyemiş ezmeleri','fats','olive','Tahin, fıstık ve badem ezmeleri; humus baklagil grubundadır.',
  '<path d="M5 8h14v13H5Zm1-5h12v5H6Z"/><path d="M9 13c1-3 5-3 6 0 1 3-5 5-6 2-1-1 0-2 1-2"/>'),
 ('olives','Zeytin','fats','olive','Yeşil ve siyah zeytin kayıtları.',
  '<path d="M5 12c-3 4 1 9 5 6s3-9 0-9-4 1-5 3Zm11-5c-4 2-4 7-1 8s7-3 5-6c-1-2-2-2-4-2Z"/><path d="m9 10 3-7m5 4-2-4m-3 0c0 3-3 4-6 2 1-3 4-3 6-2Z"/>'),
 ('hot-drinks','Sıcak içecekler','drinks','tea','Demlenmiş kahve ve çay; sunum sıcaklığı besin değerini değiştirmez.',
  '<path d="M4 9h13v7c0 6-13 6-13 0Zm13 1h2c4 0 3 5-2 5M3 22h16M7 6c-2-2 2-3 0-5m5 5c-2-2 2-3 0-5"/>'),
 ('cold-drinks','Soğuk içecekler ve meyve suları','drinks','blue','Meyve/sebze suları; süt ve bitkisel içecekler ayrı simgelidir.',
  '<path d="M5 7h14l-2 14H7Zm0 0h14M13 16l2-13h5"/><path d="m9 11 3 1-1 3-3-1Z"/>'),
 ('plant-drinks','Bitkisel içecekler','drinks','sage','Soya, badem ve yulaf içecekleri; protein içeceği olarak etiketlenmez.',
  '<path d="M8 3h7l3 5v13H6V8Zm0 0v5h10"/><path d="M14 11c-6-1-7 5-3 6 3 1 5-3 3-6Zm-5 8 4-6"/>'),
 ('smoothies','Smoothie','drinks','peach','Yalnız doğrulanmış smoothie kayıtları için ayrılmış simge.',
  '<path d="M5 7h14l-2 14H7ZM4 4h16v3H4Zm10 0 2-3h4M7 12c3-2 6 2 10 0"/><path d="M10 16h.1m4 1h.1"/>'),
 ('protein-drinks','Protein içecekleri','drinks','lavender','Doğrulanmış protein içecekleri için ayrılmış shaker simgesi.',
  '<path d="M7 7h10l2 3-2 11H7L5 10Zm1-4h8v4H8Zm2-2h4v2h-4"/><path d="m13 11-3 4h4l-3 4M5 10h14"/>'),
 ('water','Su','drinks','blue','Doğrulanmış su kayıtları için ayrılmış simge.',
  '<path d="M12 2C7 9 4 12 4 16c0 8 16 8 16 0 0-4-3-7-8-14Z"/><path d="M8 16c0 2 1 3 3 3"/>'),
 ('sauces','Soslar','condiments','peach','Domates sosu, salça, hardal, ketçap, mayonez ve salata sosları.',
  '<path d="M9 3h6v4l3 4v10H6V11l3-4Zm0 4h6M6 13h12"/><path d="M11 16h2m-1-1v2"/>'),
 ('pickles','Turşu','condiments','sage','Salatalık turşusu gibi kaynaklı turşu kayıtları.',
  '<path d="M6 3h12v4H6Zm1 4-2 3v11h14V10l-2-3"/><path d="M9 11c-3 4-1 8 1 6s3-7 1-7m4 2v5M5 18h14"/>'),
 ('spices','Baharat ve aromatikler','spices','sand','Kuru/öğütülmüş baharat, kurutulmuş ot ve tuz; taze otlar ayrı gruptadır.',
  '<path d="M8 3h8l2 5v3H6V8Zm-2 8h12l-1 10H7ZM9 6h.1m3 0h.1m3 0h.1"/><path d="m10 15 4 3m0-3-4 3"/>'),
 ('sweet-products','Şeker, bal ve reçel','sweets','peach','Şeker, bal, reçel ve tatlandırılmış meyve püresi.',
  '<path d="M6 4h12v4H6Zm1 4-2 3v10h14V11l-2-3"/><path d="M10 13c-2-2-4 1-1 3l3 2 3-2c3-2 1-5-1-3l-2 1Z"/>'),
]

TONES = {
    'wheat': ('#F8EECF','#755B1C'), 'rose': ('#F9E9E6','#8E3D42'),
    'blue': ('#EDF3F7','#335E79'), 'sand': ('#FAF0DA','#806028'),
    'sage': ('#EAF3DE','#3D7756'), 'peach': ('#FBEADF','#8B583B'),
    'olive': ('#EFF2D9','#647134'), 'tea': ('#E7EFE8','#375E45'),
    'lavender': ('#EFEAF8','#695183'),
}


def svg(body, label='', color='currentColor'):
    title = f'<title>{html.escape(label)}</title>' if label else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
            f'color="{color}" stroke="{color}" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">{title}{body}</svg>')


def attach_visuals(foods, root):
    definitions = {row[0]: row for row in DEFINITIONS}
    assignments = {}
    for line in (root / 'food-icon-map.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        fdc_id, category, _name = line.split('|')
        assert int(fdc_id) not in assignments, f'Çift ikon ataması: {fdc_id}'
        assert category in definitions, f'Bilinmeyen ikon kategorisi: {category}'
        assignments[int(fdc_id)] = category
    assert set(assignments) == {food['fdcId'] for food in foods}, 'Her kayıt için tam bir açık ikon ataması gerekir.'
    for food in foods:
        category = assignments[food['fdcId']]
        food['visualCategoryId'] = category
        food['visualGroupId'] = definitions[category][2]
    counts = Counter(assignments.values())
    groups = [{'id': i, 'labelTr': label} for i, label in GROUPS]
    categories = []
    for id_, label, group, tone, description, drawing in DEFINITIONS:
        background, color = TONES[tone]
        categories.append({'id': id_, 'labelTr': label, 'groupId': group, 'background': background,
                           'color': color, 'descriptionTr': description, 'svgBody': drawing,
                           'foodCount': counts[id_], 'isReserved': counts[id_] == 0})
    return {'name': 'Limely besin ikonları', 'version': '1.0-preview', 'viewBox': '0 0 24 24',
            'strokeWidth': 1.65, 'groups': groups, 'categories': categories,
            'mappingPolicy': 'Her FDC kaydına tek bir görsel kategori atanır. Bu bir makro dağılımı veya klinik besin değişim grubu değildir.',
            'reference': {'url': 'https://diyetisyen1.briefikir.com.tr/panel/planlar/p-d5',
                          'observedGroups': ['Tahıl','Et-balık-yumurta','Süt ürünleri','Baklagil','Sebze','Meyve','Yağ & kuruyemiş','İçecek','Atıştırmalık'],
                          'approach': 'Genel gruplar incelendi; SVG çizimleri kopyalanmadı. Daha ayrıntılı özgün Limely alt kategorileri çizildi.'}}


def export_icons(taxonomy, target):
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    for c in taxonomy['categories']:
        (target / (c['id'] + '.svg')).write_text(svg(c['svgBody'], c['labelTr'], '#203B2F') + '\n', encoding='utf-8')
    (target / 'icon-categories.json').write_text(json.dumps(taxonomy, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    symbols = ''.join(f'<symbol id="limely-food-{c["id"]}" viewBox="0 0 24 24">{c["svgBody"]}</symbol>' for c in taxonomy['categories'])
    (target / 'limely-food-sprite.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><defs>' + symbols + '</defs></svg>\n', encoding='utf-8')


def export_sheet(taxonomy, target):
    import math
    cols, cell_w, cell_h = 4, 280, 115
    rows = math.ceil(len(taxonomy['categories']) / cols)
    height = 145 + rows * cell_h + 60
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="{height}" viewBox="0 0 1200 {height}">',
             '<rect width="100%" height="100%" fill="#F8FAF2"/>',
             '<g font-family="Segoe UI,Arial,sans-serif" fill="#203B2F"><text x="40" y="53" font-size="30" font-weight="700">limely / besin ikonları</text>',
             f'<text x="40" y="87" font-size="14" fill="#52605B">{len(taxonomy["categories"])} özgün kategori · 397 besin · 24 × 24 SVG · aynı çizgi ailesi</text>']
    for i,c in enumerate(taxonomy['categories']):
        x,y = 40 + i % cols * cell_w, 120 + i // cols * cell_h
        parts += [f'<rect x="{x}" y="{y}" width="264" height="99" rx="16" fill="white" stroke="#D9DFD5"/>',
                  f'<rect x="{x+14}" y="{y+16}" width="44" height="44" rx="14" fill="{c["background"]}"/>',
                  f'<g transform="translate({x+23},{y+25}) scale(1.08)" fill="none" stroke="{c["color"]}" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">{c["svgBody"]}</g>',
                  f'<text x="{x+72}" y="{y+32}" font-size="12" font-weight="600">{html.escape(c["labelTr"])}</text>',
                  f'<text x="{x+72}" y="{y+53}" font-size="12" fill="#65735D">{str(c["foodCount"])+" besin" if c["foodCount"] else "İkon hazır · henüz besin yok"}</text>',
                  f'<text x="{x+15}" y="{y+82}" font-size="10" fill="#65735D">{c["id"]}.svg</text>']
    parts += [f'<text x="40" y="{height-25}" font-size="12" fill="#52605B">Görsel kategori önizlemesi. Besin değerleri veya proje sözleşmesi değişikliği değildir.</text></g></svg>']
    Path(target).write_text(''.join(parts)+'\n', encoding='utf-8')
