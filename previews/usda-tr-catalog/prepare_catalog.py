"""USDA Türkçe katalog önizlemesi. Yalnız Python 3.10+ standart kitaplığı.

Yeniden üretim (internet gerekmez; sources/ arşivi teslimata dahildir):
    python prepare_catalog.py
İlk arşivi USDA'dan yeniden indirmek için:
    python prepare_catalog.py --download
Doğrulama: python verify_catalog.py

selection.tsv elle seçilmiş FDC kimlikleri ve Türkçe editoryal etiketlerdir.
Besin değerleri ve gramlar bu dosyada tanımlanmaz, yalnız resmî JSON'dan okunur.
Bu biçim bir proje API/DTO/veritabanı sözleşmesi değildir.
"""

import argparse
import base64
import csv
import hashlib
import io
import json
import math
import re
from pathlib import Path
import urllib.request
import zipfile
from visual_catalog import attach_visuals, export_icons, export_sheet

ROOT = Path(__file__).resolve().parent
URL = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-10-29.zip'
RELEASE = '2026-10-29'
SOURCE_FILE = ROOT / 'sources' / 'foundation-2026-10-29.zip'
EXPECTED_SHA256 = 'dd414cc9f1a132626bad354ef6655972c78b44aff14f16114dc899708663c579'
SR_FILE = ROOT / 'sources' / 'sr-legacy-2018-04.zip'
SR_URL = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip'
SR_SHA256 = 'b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0'
KEYS = {'energyKcal': ([2048, 2047, 1008], 'kcal'),
        'proteinGrams': ([1003], 'g'), 'carbsGrams': ([1005], 'g'),
        'fatGrams': ([1004], 'g')}
CATEGORIES = {
    'Vegetables and Vegetable Products': 'Sebzeler',
    'Fruits and Fruit Juices': 'Meyveler ve meyve suları',
    'Dairy and Egg Products': 'Süt ürünleri ve yumurta',
    'Nut and Seed Products': 'Kuruyemiş ve tohumlar',
    'Poultry Products': 'Et ve kümes hayvanları',
    'Beef Products': 'Et ve kümes hayvanları',
    'Lamb, Veal, and Game Products': 'Et ve kümes hayvanları',
    'Finfish and Shellfish Products': 'Balık ve deniz ürünleri',
    'Fats and Oils': 'Yağlar ve soslar',
    'Cereal Grains and Pasta': 'Tahıl, un ve ekmek',
    'Baked Products': 'Tahıl, un ve ekmek',
    'Legumes and Legume Products': 'Baklagiller',
    'Spices and Herbs': 'Baharat ve otlar',
    'Sweets': 'Diğer temel besinler',
    'Beverages': 'İçecekler',
}
HOUSEHOLD_UNITS = {
    'cup': 'USDA cup', 'tablespoon': 'yemek kaşığı (USDA tbsp)',
    'tbsp': 'yemek kaşığı (USDA tbsp)', 'teaspoon': 'çay kaşığı (USDA tsp)',
    'tsp': 'çay kaşığı (USDA tsp)', 'piece': 'parça (USDA)',
    'slice': 'dilim (USDA)', 'egg': 'yumurta (USDA)',
    'fruit': 'meyve (USDA)', 'clove': 'diş (USDA)',
    'medium': 'orta boy (USDA)', 'large': 'büyük boy (USDA)',
    'small': 'küçük boy (USDA)', 'kernel': 'iç tane (USDA)',
    'each': 'adet (USDA)', 'drumstick': 'baget (USDA)',
    'fillet': 'fileto (USDA)', 'wedge': 'dilim parçası (USDA)',
    'can': 'konserve kutusu (USDA)', 'pieces': 'parça (USDA)',
    'onion': 'soğan (USDA)', 'banana': 'muz (USDA)',
    'tomatoes': 'domates (USDA)', 'spear': 'sap (USDA)',
    'olive': 'zeytin (USDA)', 'bunch': 'demet (USDA)',
    'roast': 'rosto parçası (USDA)', 'steak': 'biftek (USDA)',
    'sprig': 'dal (USDA)', 'leaf': 'yaprak (USDA)', 'leaves': 'yaprak (USDA)',
    'nut': 'tane (USDA)', 'nuts': 'tane (USDA)', 'kernels': 'iç tane (USDA)',
}


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def finite_positive(value):
    return isinstance(value, (int, float)) and math.isfinite(value) and value > 0


def preparation(description):
    d = description.lower()
    # Specific preparation takes precedence over a generic cooked/raw word.
    if 'par fried' in d:
        return 'Ön kızartma · fırında ısıtılmış'
    if 'hard-boiled' in d:
        return 'Katı haşlanmış'
    if 'boiled' in d:
        return 'Haşlanmış · süzülmüş' if 'drained' in d else 'Haşlanmış'
    if 'braised' in d:
        return 'Az suda pişmiş'
    if 'dry heat' in d:
        return 'Kuru ısıyla pişmiş'
    if 'moist heat' in d:
        return 'Nemli ısıyla pişmiş'
    if 'baked' in d:
        return 'Fırında pişmiş'
    if 'pan-browned' in d:
        return 'Tavada pişmiş'
    if 'poached' in d:
        return 'Poşe'
    if 'brewed' in d:
        return 'Demlenmiş'
    if 'broiled' in d:
        return 'Tavada üst ızgara usulü pişmiş' if 'pan-broiled' in d else 'Üst ızgarada pişmiş'
    if 'grilled' in d:
        return 'Izgara'
    if 'fried' in d:
        return 'Kızartılmış'
    if 'roasted' in d:
        return 'Kavrulmuş' if 'nuts' in d or 'seed' in d else 'Fırında pişmiş'
    if 'canned' in d:
        return 'Konserve · süzülmüş' if 'drained' in d else 'Konserve'
    if 'frozen' in d:
        return 'Çiğ · dondurulmuş' if 'raw' in d else 'Dondurulmuş · pişirme belirtilmemiş'
    if 'raw' in d:
        return 'Çiğ'
    if 'dried' in d:
        return 'Kurutulmuş'
    if 'dry' in d or 'uncooked' in d:
        return 'Kuru · pişmemiş'
    if 'cooked' in d or 'prepared' in d:
        return 'Pişmiş / hazırlanmış'
    return 'Kaynakta pişirme belirtilmemiş'


def nutrients(food):
    by_id = {n['nutrient']['id']: n for n in food['foodNutrients']}
    values, provenance = {}, {}
    for key, (ids, unit) in KEYS.items():
        picked = None
        for nutrient_id in ids:
            n = by_id.get(nutrient_id)
            if not n:
                continue
            if n['nutrient']['unitName'].lower() != unit:
                raise ValueError(f"Beklenmeyen birim: {food['fdcId']} {nutrient_id}")
            amount = n.get('amount')
            if amount is None:
                continue
            if not isinstance(amount, (int, float)) or not math.isfinite(amount):
                raise ValueError(f"Geçersiz değer: {food['fdcId']} {nutrient_id}")
            picked = n
            break
        values[key] = picked['amount'] if picked and picked['amount'] >= 0 else None
        provenance[key] = ({'nutrientId': picked['nutrient']['id'],
                            'nutrientNumber': picked['nutrient']['number'],
                            'name': picked['nutrient']['name'], 'unit': unit,
                            'foodNutrientId': picked.get('id'),
                            'sourceAmount': picked['amount'],
                            'quality': 'negativeSourceValue' if picked['amount'] < 0 else 'usable',
                            'loq': picked.get('loq')} if picked else None)
    return values, provenance


def portions(food, release_date):
    result = []
    for p in food.get('foodPortions', []):
        unit = p.get('measureUnit', {}).get('name', '').lower()
        if food['dataType'] == 'SR Legacy':
            # SR stores household descriptions in modifier, not measureUnit 9999.
            match = re.match(r'^([A-Za-z]+)\b', p.get('modifier', ''))
            unit = match[1].lower() if match else ''
        # RACC is a regulatory reference amount, not a household measure.
        # Do not relabel it as a slice, bowl, piece or spoon.
        if unit not in HOUSEHOLD_UNITS:
            continue
        amount, grams = p.get('amount'), p.get('gramWeight')
        if not finite_positive(amount) or not finite_positive(grams):
            continue
        qualifier = ', '.join(str(p[k]) for k in ('modifier', 'portionDescription') if p.get(k))
        label = f"{amount:g} {HOUSEHOLD_UNITS[unit]}" + (f" · {qualifier}" if qualifier else '')
        result.append({'id': str(p['id']), 'labelTr': label,
                       'sourceAmount': amount, 'gramWeight': grams,
                       'source': {'provider': 'USDA FoodData Central', 'fdcId': food['fdcId'],
                                  'releaseDate': release_date, 'foodPortion': p}})
    return result


def load_sr():
    if not SR_FILE.exists():
        raise FileNotFoundError(f'Gerçek SR Legacy arşivi bulunamadı: {SR_FILE}')
    if hashlib.sha256(SR_FILE.read_bytes()).hexdigest() != SR_SHA256:
        raise ValueError('SR Legacy arşiv SHA-256 uyuşmuyor.')
    selected_ids = {int(line.split('|')[0]) for line in (ROOT / 'selection-sr.tsv').read_text(encoding='utf-8').splitlines() if line and not line.startswith('#')}
    with zipfile.ZipFile(SR_FILE) as archive:
        def rows(name):
            member = next(n for n in archive.namelist() if n.endswith('/' + name))
            return csv.DictReader(io.TextIOWrapper(archive.open(member), encoding='utf-8-sig'))
        categories = {r['id']: r['description'] for r in rows('food_category.csv')}
        units = {r['id']: r['name'] for r in rows('measure_unit.csv')}
        nutrient_defs = {r['id']: r for r in rows('nutrient.csv')}
        foods = {}
        for row in rows('food.csv'):
            i = int(row['fdc_id'])
            if i in selected_ids:
                assert row['data_type'] == 'sr_legacy_food'
                foods[i] = {'fdcId': i, 'description': row['description'], 'dataType': 'SR Legacy',
                            'publicationDate': row['publication_date'],
                            'foodCategory': {'description': categories.get(row['food_category_id'], '')},
                            'foodNutrients': [], 'foodPortions': [],
                            'originalCsvRows': {'food': row, 'food_nutrient': [], 'food_portion': []}}
        for row in rows('sr_legacy_food.csv'):
            if int(row['fdc_id']) in foods:
                foods[int(row['fdc_id'])]['ndbNumber'] = row['NDB_number']
        for row in rows('food_nutrient.csv'):
            i = int(row['fdc_id'])
            if i not in foods or int(row['nutrient_id']) not in (1003, 1004, 1005, 1008, 2047, 2048):
                continue
            definition = nutrient_defs[row['nutrient_id']]
            foods[i]['foodNutrients'].append({'id': int(row['id']), 'amount': float(row['amount']) if row['amount'] else None,
                                             'nutrient': {'id': int(row['nutrient_id']), 'number': definition['nutrient_nbr'],
                                                          'unitName': definition['unit_name'], 'name': definition['name']}})
            foods[i]['originalCsvRows']['food_nutrient'].append(row)
        for row in rows('food_portion.csv'):
            i = int(row['fdc_id'])
            if i not in foods:
                continue
            foods[i]['foodPortions'].append({'id': int(row['id']), 'amount': float(row['amount']) if row['amount'] else None,
                                            'gramWeight': float(row['gram_weight']) if row['gram_weight'] else None,
                                            'measureUnit': {'id': int(row['measure_unit_id']), 'name': units[row['measure_unit_id']]},
                                            'modifier': row['modifier'], 'portionDescription': row['portion_description']})
            foods[i]['originalCsvRows']['food_portion'].append(row)
    assert set(foods) == selected_ids
    return foods


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--icons-out', type=Path, help='İsteğe bağlı ayrı SVG teslim klasörü')
    args = parser.parse_args()
    if args.download:
        SOURCE_FILE.parent.mkdir(exist_ok=True)
        for target, url, expected in ((SOURCE_FILE, URL, EXPECTED_SHA256), (SR_FILE, SR_URL, SR_SHA256)):
            with urllib.request.urlopen(url, timeout=120) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError('Kaynak SHA-256 uyuşmuyor; mevcut dosya korunuyor.')
            target.write_bytes(data)
    if not SOURCE_FILE.exists():
        raise SystemExit(f'Gerçek USDA arşivi bulunamadı: {SOURCE_FILE}. --download ile indirin. Sentetik veri üretilmedi.')
    digest = hashlib.sha256(SOURCE_FILE.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError('Kaynak arşiv SHA-256 uyuşmuyor.')
    with zipfile.ZipFile(SOURCE_FILE) as archive:
        names = [n for n in archive.namelist() if n.endswith('.json')]
        assert len(names) == 1
        original = json.loads(archive.read(names[0]))['FoundationFoods']
    by_id = {f['fdcId']: f for f in original}
    sr_foods = load_sr()
    assert not set(by_id).intersection(sr_foods)
    by_id.update(sr_foods)
    foods, seen = [], set()
    lines = ((ROOT / 'selection.tsv').read_text(encoding='utf-8') + '\n' + (ROOT / 'selection-sr.tsv').read_text(encoding='utf-8')).splitlines()
    for line in lines:
        if not line or line.startswith('#'):
            continue
        fdc_id, name, aliases = line.split('|')
        fdc_id = int(fdc_id)
        assert fdc_id not in seen, f'Tekrar eden kimlik: {fdc_id}'
        seen.add(fdc_id)
        raw = by_id[fdc_id]
        release_date = RELEASE if raw['dataType'] == 'Foundation' else '2018-04'
        archive_sha = digest if raw['dataType'] == 'Foundation' else SR_SHA256
        assert '0% moisture' not in raw['description']
        values, mapping = nutrients(raw)
        foods.append({'fdcId': fdc_id, 'nameTr': name, 'originalName': raw['description'],
                      'aliasesTr': aliases.split(','), 'preparationTr': preparation(raw['description']),
                      'categoryTr': CATEGORIES.get(raw.get('foodCategory', {}).get('description'), 'Diğer temel besinler'),
                      'basis': {'amount': 100, 'unit': 'g', 'ediblePortion': True},
                      'per100g': values, 'nutrientMapping': mapping, 'portions': portions(raw, release_date),
                      'source': {'provider': 'USDA FoodData Central', 'dataType': raw['dataType'],
                                 'releaseDate': release_date, 'publicationDate': raw.get('publicationDate'),
                                 'ndbNumber': raw.get('ndbNumber'), 'archiveSha256': archive_sha,
                                 'url': f'https://fdc.nal.usda.gov/food-details/{fdc_id}/nutrients'}})
    foods.sort(key=lambda f: (f['nameTr'].casefold(), f['fdcId']))
    taxonomy = attach_visuals(foods, ROOT)
    catalog = {'previewFormat': 'usda-tr-preview-2', 'isProjectContract': False,
               'visualTaxonomy': taxonomy,
               'preparedOn': '2026-11-28',
               'source': {'provider': 'USDA FoodData Central', 'dataset': 'Foundation Foods + SR Legacy',
                          'datasets': [{'name': 'Foundation Foods', 'releaseDate': RELEASE, 'archiveSha256': digest, 'downloadUrl': URL},
                                       {'name': 'SR Legacy', 'releaseDate': '2018-04', 'archiveSha256': SR_SHA256, 'downloadUrl': SR_URL}],
                          'releaseDate': RELEASE, 'downloadUrl': URL, 'archiveSha256': digest,
                          'downloadPage': 'https://fdc.nal.usda.gov/download-datasets/',
                          'documentationUrl': 'https://fdc.nal.usda.gov/Foundation_Foods_Documentation/',
                          'fieldDescriptionsUrl': 'https://fdc.nal.usda.gov/docs/Download_Field_Descriptions_Oct2020.pdf',
                          'license': 'CC0 1.0 Universal', 'licenseUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
                          'licenseStatementUrl': 'https://fdc.nal.usda.gov/',
                          'citation': 'U.S. Department of Agriculture, Agricultural Research Service, Beltsville Human Nutrition Research Center. FoodData Central. Erişim: 28.11.2026. https://fdc.nal.usda.gov/'},
               'policies': {'nutrientBasis': 'foodNutrients.amount: yenilebilir 100 g; sıvılar da kaynakta 100 g. ml dönüşümü yok.',
                            'energyPriority': [2048, 2047, 1008],
                            'energy': 'Kaynakta mevcut USDA enerjisi seçilir; 4/4/9 yeniden hesaplanmaz. Alternatif enerji değerleri kaynak arşivinde saklanır.',
                            'missing': 'Eksik değer null; kaynakta negatif değer varsa hesap değeri null ve eşlemede quality=negativeSourceValue. Kaynak değer silinmez veya sıfırlanmaz. Toplamlar besin öğesi bazında kısmi işaretlenir.',
                            'portions': 'Yalnız kaynağında gram ağırlığı olan ev ölçüleri; RACC ve ağırlık birimleri ev ölçüsü sayılmaz. Miktar, seçilen kaynak porsiyonunun katıdır.',
                            'translations': 'Türkçe ad ve eş anlamlılar editoryal çeviridir; USDA doğrulaması veya yerel ürün eşdeğerliği anlamına gelmez.'},
               'limitations': ['Foundation Foods ve SR Legacy kayıtları kaynak türleri ve sürümleriyle ayrı izlenir. Aynı besinin çiğ/pişmiş kayıtları ayrıdır.',
                               'Türk yemekleri için tarif veya besin değeri üretilmedi.',
                               'ABD kayıtları Türkiye’deki belirli marka, peynir veya tarife birebir eşdeğer değildir.',
                               'Öğün yalnız açık sayfanın belleğinde tutulur; yenileyince silinir.'],
               'stats': {'foodCount': len(foods), 'foodsWithHouseholdPortions': sum(bool(f['portions']) for f in foods),
                         'foodsWithMissingValues': sum(any(v is None for v in f['per100g'].values()) for f in foods)},
               'foods': foods}
    dump(ROOT / 'catalog.json', catalog)
    export_icons(taxonomy, ROOT / 'icons')
    if args.icons_out:
        export_icons(taxonomy, args.icons_out)
        export_sheet(taxonomy, args.icons_out.parent / 'limely-besin-ikonlari.svg')
        dump(args.icons_out / 'food-icon-map.json', {'previewOnly': True, 'foodCount': len(foods),
             'foods': [{k: food[k] for k in ('fdcId', 'nameTr', 'visualCategoryId', 'visualGroupId')} for food in foods]})
    template = (ROOT / 'preview.template.html').read_text(encoding='utf-8')
    template = template.replace('__PREVIEW_CSS__', (ROOT / 'limely-preview.css').read_text(encoding='utf-8'))
    template = template.replace('__PREVIEW_SCRIPT__', (ROOT / 'preview.js').read_text(encoding='utf-8'))
    template = template.replace('__LIMELY_LOGO__', base64.b64encode((ROOT / 'assets' / 'limely-logo.svg').read_bytes()).decode('ascii'))
    embedded = json.dumps(catalog, ensure_ascii=False, separators=(',', ':'), allow_nan=False).replace('<', '\\u003c')
    for font in ('inter', 'manrope'):
        encoded = base64.b64encode((ROOT / 'assets' / 'fonts' / font / (font + '.ttf')).read_bytes()).decode('ascii')
        template = template.replace('__' + font.upper() + '_FONT__', encoded)
    (ROOT / 'index.html').write_text(template.replace('__CATALOG_JSON__', embedded), encoding='utf-8')
    # Compact, unmodified source records allow independent per-field comparisons.
    dump(ROOT / 'sources' / 'selected-usda-records.json', [by_id[i] for i in sorted(seen)])
    print(json.dumps(catalog['stats'], ensure_ascii=False))
    print('index.html ve catalog.json aynı katalogdan üretildi.')


if __name__ == '__main__':
    main()
