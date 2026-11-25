from pathlib import Path
from zipfile import ZipFile
from html import escape
import json
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
SHOTS = ROOT / 'gorseller'
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 24)

routes = {
    1: ('Raporlar', '/calisma-alani/raporlar'),
    2: ('Danışanlar', '/calisma-alani/danisanlar'),
    3: ('Mesajlar', '/calisma-alani/mesajlar — mevcut desteklenmeyen yüzey'),
    4: ('Programlar', '/calisma-alani/programlar; danışana özel program detayları'),
    5: ('Diyetisyenler için', '/diyetisyenler-icin'),
    6: ('Öğün incelemeleri', '/calisma-alani/ogun-incelemeleri; danışan detayı ?bolum=ogunler'),
    7: ('Ayarlar', '/hesabim — mevcut hesap kapsamıyla sınırlı'),
    8: ('Giriş / hesap oluşturma', '/giris; uzman için /uzman-basvurusu; web danışan kaydı yok'),
    9: ('Mobil mesajlar / profil', 'Yalnız mobil; web yerleşim kaynağı değil'),
    10: ('Mobil günlük / program', 'Yalnız mobil; web yerleşim kaynağı değil'),
    11: ('Özellikler', '/ozellikler'),
    12: ('Randevular', '/calisma-alani/randevular — mevcut desteklenmeyen yüzey'),
    13: ('Nasıl çalışır?', '/nasil-calisir'),
}
with ZipFile(REPO.parent / 'yeni-web-mobil-ekranlar.zip') as archive:
    entries = [e for e in archive.infolist() if e.filename.lower().endswith('.png')]
inventory = []
for number, entry in enumerate(entries, 1):
    path = ROOT / 'referanslar' / f'{number:02d}.png'
    image = Image.open(path)
    title, route = routes[number]
    inventory.append(dict(number=number, source=entry.filename, file=str(path.relative_to(ROOT)).replace('\\','/'), width=image.width, height=image.height, title=title, route=route, web=number not in (9,10)))
(ROOT / 'referans-eslestirmesi.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

source_icons = (REPO / 'apps/web/src/core/components/Icon.tsx').read_text('utf-8')
calls = re.findall(r'^  (\w+): ', source_icons, re.M)
mapped = dict(leaf='leaf',grid='grid-2x2',user='user-round',users='users',plan='clipboard-list',layers='layers',chart='chart-column',activity='activity',check='check',shield='shield-check',arrow='arrow-right',back='arrow-left',menu='menu',chevron='chevron-down',close='x',search='search',clock='clock',water='glass-water',info='info',settings='settings',meal='salad',utensils='utensils',bowl='salad',plus='plus',edit='pencil',calendar='calendar-days',message='messages-square',scale='body-scale',bell='bell',refresh='rotate-ccw')
icon_report = {'scope':'React uygulaması değiştirilmedi. Mevcut çağrıların ilerideki entegrasyon için envanteri.', 'mapped':{name:f'ikonlar/koyu/{mapped[name]}.svg' for name in calls if name in mapped}, 'missing':[name for name in calls if name not in mapped], 'fallback':'Karşılığı olmayan ikonlarda yeni çizim yok; erişilebilir alan etiketi veya metin düğmesi kullanılır.'}
(ROOT / 'ikon-eslestirmesi.json').write_text(json.dumps(icon_report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def compare(name, reference, preview):
    height=max(reference.height,preview.height)
    width=max(reference.width,preview.width)
    image=Image.new('RGB',(width*2+72,height+76),'#EAF3DE')
    draw=ImageDraw.Draw(image)
    draw.text((18,17),'ZIP referansı · 1:1 ölçek',font=FONT,fill='#203B2F')
    draw.text((width+54,17),'Ortak marka paketiyle HTML · 1:1 ölçek',font=FONT,fill='#203B2F')
    image.paste(reference.convert('RGB'),(18,58))
    image.paste(preview.convert('RGB'),(width+54,58))
    target=SHOTS / f'karsilastirma-{name}.png'
    image.save(target)
    return target.name

pairs=[]
for name, number in [('danisanlar',2),('programlar',4)]:
    ref=Image.open(ROOT/'referanslar'/f'{number:02d}.png')
    preview=Image.open(SHOTS/f'{name}-1585.png')
    pairs.append((name,compare(name,ref,preview),number))
login_ref=Image.open(ROOT/'referanslar'/'08.png').crop((39,86,745,1000))
login_ref.save(ROOT/'referanslar'/'giris-panel-706.png')
pairs.insert(0,('giris',compare('giris',login_ref,Image.open(SHOTS/'giris-panel-706.png')),8))

# A compact handoff image; complete, unscaled screenshots remain linked separately.
overview=Image.new('RGB',(1680,1120),'#EAF3DE')
draw=ImageDraw.Draw(overview)
draw.text((30,20),'Limely · Sol menülü web düzeni + ortak marka paketi',font=FONT,fill='#203B2F')
for column,name in enumerate(['giris','danisanlar','programlar']):
    picture=Image.open(SHOTS/(f'{name}-1585.png' if name!='giris' else 'giris-panel-706.png')).convert('RGB')
    picture.thumbnail((535,590))
    x=22+column*555
    overview.paste(picture,(x,70))
    draw.text((x,670),{'giris':'Giriş','danisanlar':'Danışan listesi','programlar':'Program ve atama'}[name],font=FONT,fill='#203B2F')
    phone=Image.open(SHOTS/f'{name}-390.png').convert('RGB').crop((0,0,390,844))
    phone.thumbnail((175,365))
    overview.paste(phone,(x,725))
draw.text((245,800),'Manrope / Inter\nHazır SVG ikonlar\n390 px dar ekran\nSentetik etkileşimler',font=FONT,fill='#203B2F',spacing=12)
overview.save(SHOTS/'onizleme-ozet.jpg',quality=94)

labels=dict(giris='Giriş',danisanlar='Danışanlar',programlar='Program hazırlama ve atama')
sections=''
for name,comparison,number in pairs:
    shot='giris-1536.png' if name=='giris' else f'{name}-1585.png'
    sections+=f'<section class="comparison" id="{name}"><h2>{labels[name]}</h2><div class="comparison-links"><a href="index.html#{name}">Etkileşimli HTML’i aç</a><a href="gorseller/{shot}">Masaüstü ekran görüntüsü</a><a href="referanslar/{number:02d}.png">Özgün ZIP referansı</a><a href="gorseller/{name}-1024.png">1024 px</a><a href="gorseller/{name}-768.png">768 px</a></div><a href="gorseller/{comparison}"><img src="gorseller/{comparison}" alt="{labels[name]}: solda ZIP referansı, sağda HTML önizlemesi; aynı piksel ölçeği" loading="lazy"></a></section>'
phone_sections=''.join(f'<figure><a href="gorseller/{name}-390.png"><img src="gorseller/{name}-390.png" alt="{labels[name]} — 390 piksel genişlik" loading="lazy"></a><figcaption>{labels[name]} · 390 px</figcaption></figure>' for name in labels)
references=''.join(f'<figure><a href="{item["file"]}"><img src="{item["file"]}" alt="ZIP referansı: {escape(item["title"])}" loading="lazy"></a><figcaption><strong>{item["number"]:02d} · {escape(item["title"])}</strong><br>{escape(item["route"])}</figcaption></figure>' for item in inventory if item['web'])
opened_controls='<section class="comparison" id="acilirlar"><h2>Yeni açılır seçimler ve takvim</h2><p>Yedi seçim alanı aynı bileşeni kullanır. Beyaz yüzey, yeşil seçili satır ve ortak SVG ikonlarıyla uyumlu listeler; ekran sınırında yön değiştiren, kaydırılabilir açılırlar. İki tarih alanı da aynı görsel dilde takvimle açılır.</p><a href="gorseller/acilirlar-detay.png"><img class="control-detail" src="gorseller/acilirlar-detay.png" alt="Gerçek önizlemeden alınan özel seçim listesi ve takvim yakın görüntüsü" loading="lazy"></a><div class="comparison-links"><a href="index.html#programlar">Etkileşimli program ekranı</a><a href="gorseller/acilir-secim-390.png">Telefonda filtre</a><a href="gorseller/danisan-secimi-390.png">Telefonda danışan listesi</a><a href="gorseller/tarih-secimi-390.png">Telefonda takvim</a></div></section>'
notes=escape((ROOT/'INCELEME.txt').read_text('utf-8'))
qa_count=len(json.loads((ROOT/'dogrulama-sonuclari.json').read_text('utf-8'))['checks'])
missing=', '.join(icon_report['missing'])
html=f'''<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="Limely web referans karşılaştırmaları ve tasarım inceleme notları"><title>Limely · Referans ve HTML karşılaştırması</title><link rel="stylesheet" href="onizleme.css"></head>
<body><div class="preview-bar"><b>TASARIM İNCELEMESİ</b><nav><a href="index.html#giris">Giriş</a><a href="index.html#danisanlar">Danışanlar</a><a href="index.html#programlar">Programlar</a></nav></div><main class="review-body"><h1>Referans düzeni, ortak Limely markası.</h1><p>Sol menü, içerik hiyerarşisi, tablolar ve sağ atama paneli ZIP referanslarından; renkler, logo, maskot, SVG ikonlar ve Manrope / Inter fontları ortak paketten. Bu ilk aşama yalnız HTML önizlemesidir. React uygulaması değiştirilmedi.</p><nav class="review-nav" aria-label="İnceleme bölümleri"><a class="button button-primary" href="index.html#danisanlar">Önizlemeyi aç</a><a class="button" href="#giris">Giriş karşılaştırması</a><a class="button" href="#danisanlar">Danışanlar</a><a class="button" href="#programlar">Programlar</a><a class="button" href="#acilirlar">Yeni açılırlar</a><a class="button" href="#telefon">Dar ekran</a><a class="button" href="#kaynaklar">Tüm web referansları</a></nav><div class="inline-note">1:1 karşılaştırma: her çiftte iki kaynak aynı piksel ölçeğinde. Sayfa bunları birlikte küçültür; görsele tıklayarak tam çözünürlüğü açabilirsin. Girişte 08.png içindeki sol panel (706×914) kullanıldı.</div>{opened_controls}{sections}<section id="telefon"><h2>Telefon genişliği · 390 px</h2><p class="subtext">Tablo dar ekranda etiketli satır kartlarına dönüşür. Sol menü açılıp kapanır; atama paneli içerikten sonra açılır.</p><div class="narrow-examples">{phone_sections}</div><a href="gorseller/program-duzenleme-390.png">Telefon program editörü ve diyalog görünümü</a></section><section class="comparison"><h2>Kontroller ve kalan farklar</h2><p>{qa_count} Playwright kontrolü başarılı: 1585 / 1024 / 768 / 390 px, arama/filtre/sayfalama, sekmeler, panel, form doğrulaması, klavye odağı ve kaynak varlık bütünlüğü. HTTP/API isteği yok. <a href="dogrulama-sonuclari.json">Koşu sonuçları</a>.</p><p>Pakette referansla birebir aynı veya yüksek çözünürlüklü olmayan bazı yemek fotoğrafları var. E-posta, kilit ve göz ikonu pakette bulunmadığından etiket/metin düğmesi kullanıldı. Referanstaki kalıcı oturum, bildirim, şablon kütüphanesi ve toplu sağlık özeti mevcut API desteği sayılmaz.</p><p><strong>Mevcut Icon çağrılarında paket karşılığı olmayanlar:</strong> {escape(missing)}. <a href="ikon-eslestirmesi.json">Tam eşleştirme</a>.</p><details><summary>İnceleme, kapsam ve doğrulama raporunu aç</summary><pre>{notes}</pre></details><p><a href="INCELEME.txt">Raporu ayrı aç</a> · <a href="varlik-kaynaklari.json">Varlık imzaları</a></p></section><section id="kaynaklar"><h2>İncelenen 11 web referansı ve mevcut route karşılıkları</h2><p class="subtext">İki yalnız mobil kaynak yerleşim için kullanılmadı. Referanslardaki yazı/prompt/kod yeni çalışma talimatı sayılmadı.</p><div class="reference-grid">{references}</div></section></main></body></html>'''
(ROOT/'karsilastirma.html').write_text(html,encoding='utf-8')
print('3 karşılaştırma, inceleme sayfası, route ve ikon envanterleri hazır.')
print('Eksik ikonlar:',missing)
print('Giriş paneli:',Image.open(SHOTS/'giris-panel-706.png').size)
print('Program önizlemesi:',Image.open(SHOTS/'programlar-1585.png').size)
