"""Bağımsız aktarım denetimi: python verify_catalog.py (ağ/paket gerekmez)."""
import hashlib
import csv
import io
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parent


def verify():
    catalog = json.loads((ROOT / 'catalog.json').read_text(encoding='utf-8'))
    html = (ROOT / 'index.html').read_text(encoding='utf-8')
    embedded = json.loads(re.search(r'<script type="application/json" id="catalog-data">(.*?)</script>', html, re.S)[1])
    assert embedded == catalog, 'HTML ve JSON farklı'
    path = ROOT / 'sources' / 'foundation-2026-10-29.zip'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == catalog['source']['archiveSha256']
    with zipfile.ZipFile(path) as archive:
        raw = json.loads(archive.read(archive.namelist()[0]))['FoundationFoods']
    original = {food['fdcId']: food for food in raw}
    sr_path = ROOT / 'sources' / 'sr-legacy-2018-04.zip'
    assert hashlib.sha256(sr_path.read_bytes()).hexdigest() == catalog['source']['datasets'][1]['archiveSha256']
    selected_ids = {str(f['fdcId']) for f in catalog['foods'] if f['source']['dataType'] == 'SR Legacy'}
    with zipfile.ZipFile(sr_path) as archive:
        def read_table(name):
            filename = next(n for n in archive.namelist() if n.endswith('/' + name))
            return csv.DictReader(io.TextIOWrapper(archive.open(filename), encoding='utf-8-sig'))
        sr_food_rows = {r['fdc_id']: r for r in read_table('food.csv') if r['fdc_id'] in selected_ids}
        sr_nutrients = {r['id']: r for r in read_table('nutrient.csv')}
        sr_units = {r['id']: r['name'] for r in read_table('measure_unit.csv')}
        for i, row in sr_food_rows.items():
            assert row['data_type'] == 'sr_legacy_food'
            original[int(i)] = {'fdcId': int(i), 'description': row['description'], 'publicationDate': row['publication_date'],
                                 'dataType': 'SR Legacy', 'foodNutrients': [], 'foodPortions': []}
        for row in read_table('food_nutrient.csv'):
            if row['fdc_id'] in selected_ids:
                n = sr_nutrients[row['nutrient_id']]
                original[int(row['fdc_id'])]['foodNutrients'].append({'id': int(row['id']),
                    'amount': float(row['amount']) if row['amount'] else None,
                    'nutrient': {'id': int(row['nutrient_id']), 'unitName': n['unit_name']}})
        for row in read_table('food_portion.csv'):
            if row['fdc_id'] in selected_ids:
                original[int(row['fdc_id'])]['foodPortions'].append({'id': int(row['id']),
                    'amount': float(row['amount']) if row['amount'] else None,
                    'gramWeight': float(row['gram_weight']) if row['gram_weight'] else None,
                    'modifier': row['modifier'], 'portionDescription': row['portion_description'],
                    'measureUnit': {'id': int(row['measure_unit_id']), 'name': sr_units[row['measure_unit_id']]}})
    assert len(set(food['fdcId'] for food in catalog['foods'])) == len(catalog['foods'])
    assert len(set(food['nameTr'] for food in catalog['foods'])) == len(catalog['foods'])
    mapping = {'proteinGrams': 1003, 'carbsGrams': 1005, 'fatGrams': 1004}
    compared, missing, invalid, portions = 0, 0, 0, 0
    for food in catalog['foods']:
        source = original[food['fdcId']]
        assert source['description'] == food['originalName']
        assert food['basis'] == {'amount': 100, 'unit': 'g', 'ediblePortion': True}
        assert food['source']['dataType'] == source['dataType']
        assert food['source']['publicationDate'] == source.get('publicationDate')
        assert food['source']['releaseDate'] == ('2026-10-29' if source['dataType'] == 'Foundation' else '2018-04')
        nutrients = {n['nutrient']['id']: n for n in source['foodNutrients']}
        energy_id = next((i for i in (2048, 2047, 1008) if nutrients.get(i, {}).get('amount') is not None), None)
        for key, nutrient_id in dict(mapping, energyKcal=energy_id).items():
            nutrient = nutrients.get(nutrient_id)
            amount = nutrient.get('amount') if nutrient else None
            if amount is None:
                missing += 1
                assert food['per100g'][key] is None
                assert food['nutrientMapping'][key] is None
            else:
                expected_unit = 'kcal' if key == 'energyKcal' else 'g'
                assert nutrient['nutrient']['unitName'].lower() == expected_unit
                assert food['nutrientMapping'][key]['nutrientId'] == nutrient_id
                assert food['nutrientMapping'][key]['sourceAmount'] == amount
                if amount < 0:
                    invalid += 1
                    assert food['per100g'][key] is None
                    assert food['nutrientMapping'][key]['quality'] == 'negativeSourceValue'
                else:
                    assert food['per100g'][key] == amount
                    compared += 1
        source_portions = {str(p['id']): p for p in source.get('foodPortions', [])}
        for portion in food['portions']:
            p = source_portions[portion['id']]
            assert portion['source']['foodPortion'] == p
            assert portion['source']['fdcId'] == food['fdcId']
            assert portion['gramWeight'] == p['gramWeight'] > 0
            assert portion['sourceAmount'] == p['amount'] > 0
            assert p['measureUnit']['name'] not in ('RACC', 'oz', 'milliliter')
            portions += 1
    index = {f['fdcId']: f for f in catalog['foods']}
    assert index[2646170]['preparationTr'] == 'Çiğ'
    assert index[331960]['preparationTr'] == 'Az suda pişmiş'
    assert index[326196]['preparationTr'] == 'Haşlanmış · süzülmüş'
    assert index[324317]['preparationTr'] == 'Ön kızartma · fırında ısıtılmış'
    assert not index[2710820]['portions'], 'RACC ev ölçüsü sayılmamalı'
    assert index[2346394]['per100g']['energyKcal'] == 679  # USDA specific energy, not 730 general
    assert catalog['stats']['foodCount'] == len(catalog['foods'])
    assert catalog['stats']['foodsWithHouseholdPortions'] == sum(bool(f['portions']) for f in catalog['foods'])
    assert 'fetch(' not in html
    assert not re.search(r'<(?:script|link|img)\b[^>]*(?:src|href)=["\'](?:https?:|/)', html)
    result = {'foods': len(catalog['foods']), 'householdPortionFoods': catalog['stats']['foodsWithHouseholdPortions'],
              'exactNutrientComparisons': compared, 'missingNutrientsPreservedAsNull': missing,
              'negativeSourceValuesRetainedButNotCalculated': invalid, 'exactPortionComparisons': portions,
              'embeddedJsonMatches': True, 'archiveSha256Matches': True}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return result


if __name__ == '__main__':
    verify()
