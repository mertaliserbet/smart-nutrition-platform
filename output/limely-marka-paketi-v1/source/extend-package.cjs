const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
let sharp;
try { sharp = require('sharp'); }
catch { sharp = require('C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1123-915-0_26.1123.915.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules/sharp'); }
const { trace, shape, foreground, fillHoles, defs } = require('./build-assets.cjs');
const root = path.resolve(__dirname, '..');
const concepts = path.resolve(root, '../limely-tasarim-konseptleri');
const repo = path.resolve(root, '../..');
const manifestPath = path.join(root, 'asset-manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const original = JSON.parse(fs.readFileSync(path.join(__dirname, 'korunan-varliklar-sha256.json'), 'utf8'));
const baseIds = new Set(Object.keys(original).filter(f => f.endsWith('.svg')).map(f => path.basename(f, '.svg')));
const assets = manifest.assets.filter(a => baseIds.has(a.id)).map(a => ({...a,category:a.svg.startsWith('maskotlar/')?'mascot':'brand'}));
const files = [];
const hash = buffer => crypto.createHash('sha256').update(buffer).digest('hex');
const xml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
function write(relative, content) { const dest = path.join(root, relative); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, content); return dest; }
function copy(source, relative, purpose, status = 'source') {
  const data = fs.readFileSync(source); write(relative, data);
  files.push({ file: relative, sha256: hash(data), purpose, status });
}
async function asset(relative, title, inner, options = {}) {
  const { width = 24, height = width, pngWidth = 96, category = 'icon', source = 'Limely çizimi', opaque = false } = options;
  const svg = `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-labelledby="asset-title"><title id="asset-title">${xml(title)}</title>${inner}</svg>\n`;
  write(relative + '.svg', svg);
  await sharp(Buffer.from(svg)).resize({ width: pngWidth }).png().toFile(path.join(root, relative + '.png'));
  const meta = await sharp(path.join(root, relative + '.png')).metadata();
  assets.push({ id: relative.replaceAll('/', '-'), title, svg: relative + '.svg', png: relative + '.png', width: meta.width, height: meta.height, category, source, opaque });
}
const outline = (body, color = '#203B2F', weight = 1.8) => `<g fill="none" stroke="${color}" stroke-width="${weight}" stroke-linecap="round" stroke-linejoin="round">${body}</g>`;

async function measurementMascot() {
  const crop = { left: 1048, top: 192, width: 173, height: 181 };
  const { data, info } = await sharp(path.join(root, 'referanslar/limely-karsilama-ekranlari.png')).extract(crop).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const count = info.width * info.height;
  const visible = new Uint8Array(count);
  const masks = Object.fromEntries(['leaf', 'vein', 'rind', 'ink', 'pith', 'citrus', 'tape'].map(k => [k, new Uint8Array(count)]));
  for (let i = 0; i < count; i++) visible[i] = foreground(...data.subarray(i * 3, i * 3 + 3)) ? 1 : 0;
  const silhouette = fillHoles(visible, info.width, info.height);
  for (let i = 0; i < count; i++) {
    if (!silhouette[i]) continue;
    const x = i % info.width, y = (i / info.width) | 0, [r, g, b] = data.subarray(i * 3, i * 3 + 3);
    const colors = { body:[136,185,117], leaf:[61,129,82], ink:[28,62,42], pith:[252,249,227], citrus:[248,213,98] };
    if (y < 126 || x < 45 || x > 145) colors.tape = [235,220,29];
    let best = 'body', distance = Infinity;
    for (const [key, rgb] of Object.entries(colors)) {
      const d = (r-rgb[0])**2 + (g-rgb[1])**2 + (b-rgb[2])**2;
      if (d < distance) { distance=d; best=key; }
    }
    if (best === 'leaf') best = y < 65 ? 'leaf' : 'rind';
    if (y < 61 && r > 150 && g > 175 && b < 170) best='vein';
    if (best !== 'body') masks[best][i]=1;
  }
  let inner = defs + shape(trace(silhouette, info.width, info.height, 3), 'url(#body)');
  for (const [name, fill] of [['leaf','url(#leaf)'],['vein','#A8CD82'],['rind','url(#rind)'],['pith','#FFF9E6'],['citrus','url(#yellow)'],['tape','#E8D633'],['ink','#203B2F']]) inner += `<g id="${name}">${shape(trace(masks[name], info.width, info.height, name === 'pith' ? 6 : .7), fill, ` stroke="${fill}" stroke-width="${name==='pith'||name==='citrus'?.8:.2}" stroke-linejoin="round"`)}</g>`;
  await asset('maskotlar/limely-maskot-olcum', 'Mezura tutan Limely — seni tanıyalım', `<g transform="translate(83 54) scale(4.95)">${inner}</g>`, { width:1024, pngWidth:2048, category:'mascot', source:'referanslar/limely-karsilama-ekranlari.png; crop 1048,192,173,181' });
}

async function icons() {
  const sources = fs.readdirSync(path.join(__dirname, 'lucide')).filter(f => f.endsWith('.svg')).sort();
  const custom = {
    'body-scale': '<rect x="3" y="3" width="18" height="18" rx="4"/><path d="M7 10a5 5 0 0 1 10 0M12 10l2-3M8 7l.5 1M16 7l-.5 1"/>',
    'height': '<circle cx="8" cy="4" r="2"/><path d="M4 13v-3a4 4 0 0 1 8 0v3M6 21v-8m4 8v-8M18 3v18m-3-15 3-3 3 3m-6 12 3 3 3-3"/>',
    'walk': '<circle cx="14" cy="3.5" r="1.8"/><path d="m8 21 3-7-2-4 3-4 3 5 4 1M4 12l4-1 3-4m2 7 3 7"/>',
    'run': '<circle cx="16" cy="3.5" r="1.8"/><path d="m4 21 4-6 4 1 2 5m-5-8 3-6 4 4 5-1M3 9l5 1 4-3"/>',
  };
  for (const name of [...sources.map(f => f.slice(0, -4)), ...Object.keys(custom)]) {
    const content = custom[name] || fs.readFileSync(path.join(__dirname, 'lucide', name + '.svg'), 'utf8').replace(/^[\s\S]*?<svg\b[^>]*>/, '').replace(/<\/svg>[\s\S]*$/, '');
    for (const [variant, color] of [['koyu','#203B2F'],['beyaz','#FFFFFF']]) await asset(`ikonlar/${variant}/${name}`, `${name} — ${variant}`, outline(content, color), { source: custom[name] ? 'Limely özel çizim; ekran referansı' : 'Lucide 7981a0798a4f7184296bf42e94b6a8677f3ef2a0; lisanslar/LUCIDE-LICENSE.txt' });
  }
}

async function components() {
  for (const [name, level] of [['bos',0],['az',.25],['yari',.5],['dolu',1]]) {
    const fillY = 75 - level * 51;
    const silhouette = 'M31 13V7h18v6l-2 4v6l9 10v40a8 8 0 0 1-8 8H32a8 8 0 0 1-8-8V33l9-10v-6Z';
    const body = `<defs><clipPath id="bottle"><path d="${silhouette}"/></clipPath></defs><g clip-path="url(#bottle)"><rect x="20" y="${fillY}" width="40" height="58" fill="#C3DDA7"/></g>${outline(`<path d="${silhouette}"/><path d="M32 13h16"/>`, '#3D7756', 2)}`;
    await asset(`bilesenler/su-sisesi-${name}`, `Su şişesi — ${name}`, body, { width:80,height:90,pngWidth:320,category:'component' });
  }
  for (const [name, filled] of [['bos',false],['dolu',true]]) await asset(`bilesenler/su-bardagi-${name}`, `Su bardağı — ${name}`, `<path d="M10 11Q25 5 40 11L36 48Q25 53 14 48Z" fill="${filled ? '#83B977' : 'none'}" stroke="#203B2F" stroke-width="2"/>${filled ? '<path d="M16 17L18 32" stroke="#F8FAF2" stroke-width="2" stroke-linecap="round"/>' : ''}`, { width:50,height:60,pngWidth:200,category:'component' });
  await asset('bilesenler/secim-bos', 'Seçim — seçilmemiş', '<circle cx="12" cy="12" r="9" fill="none" stroke="#9AA791" stroke-width="1.8"/>', {category:'component'});
  await asset('bilesenler/secim-dolu', 'Seçim — seçilmiş', '<circle cx="12" cy="12" r="9" fill="#203B2F"/><path d="m7.5 12 3 3 6-6" fill="none" stroke="#FFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>', {category:'component'});
  await asset('bilesenler/bildirim-noktasi', 'Bildirim işareti', '<circle cx="12" cy="12" r="6" fill="#F5D96A"/>', {category:'component'});
  for (const [name, color] of [['tamam','#C9E879'],['bekleyen','#E3ECD9']]) await asset(`bilesenler/ilerleme-adimi-${name}`, `Tanışma adımı — ${name}`, `<rect x="3" y="5" width="114" height="6" rx="3" fill="${color}"/>`, {width:120,height:16,pngWidth:480,category:'component'});
  await asset('bilesenler/enerji-gostergesi-ornek', 'Enerji göstergesi — yalnız görsel örnek', '<rect x="4" y="8" width="312" height="10" rx="5" fill="#E3ECD9"/><rect x="4" y="8" width="89" height="10" rx="5" fill="#C9E879"/>', {width:320,height:26,pngWidth:960,category:'component'});
  await asset('bilesenler/aktif-sekme-cizgisi', 'Aktif sekme çizgisi', '<rect x="5" y="7" width="38" height="4" rx="2" fill="#203B2F"/>', {width:48,height:18,pngWidth:192,category:'component'});
  await asset('dekorlar/maskot-halesi', 'Karşılama maskot halesi', '<ellipse cx="160" cy="160" rx="150" ry="148" fill="#EAF3DE"/>', {width:320,pngWidth:960,category:'decoration'});
  await asset('dekorlar/iki-cekirdek', 'Karşılama çekirdek süsleri', '<path d="M18 5C6-1 4 19 14 23C25 27 29 10 18 5ZM7 31C-2 27-1 39 11 42C23 45 18 33 7 31Z" fill="#8DBD4C"/>', {width:38,height:50,pngWidth:152,category:'decoration'});
  await asset('dekorlar/panel-koyu-banner', 'Panel koyu yeşil zemin ve organik şekiller', '<rect x="2" y="2" width="1196" height="196" rx="24" fill="#203B2F"/><path d="M680 198C730 163 745 74 859 67C962 62 955 145 1077 153C1137 157 1170 123 1198 128V198Z" fill="#365942"/><path d="M775 198C852 139 928 168 1004 122C1107 60 1156 84 1198 107V198Z" fill="#44704F" opacity=".6"/>', {width:1200,height:200,pngWidth:1800,category:'decoration'});
  for (const [name, color] of [['yesil','#DEF1E5'],['sari','#FFF1C4'],['pembe','#FBE7EE']]) await asset(`dekorlar/kart-kose-${name}`, `İstatistik kartı köşe şekli — ${name}`, `<path d="M8 112A104 104 0 0 1 112 8V112Z" fill="${color}"/>`, {width:120,pngWidth:360,category:'decoration'});
}

function sourceFiles() {
  for (const file of ['limely-danisan-yeni-duzen-v3.png','limely-diyetisyen-yeni-duzen-v3.png','limely-karsilama-ekranlari.png','limely-panel-tipografi-v2.png','limely-panel.png','limely-karsilama.html','uretim-promptlari.json','tipografi-v2-promptlari.json','yeni-duzen-v3-promptlari.json']) copy(fs.existsSync(path.join(concepts,file)) ? path.join(concepts,file) : path.join(root,'referanslar',file), `referanslar/${file}`, 'Özgün konsept ve üretim kaynağı; uygulama kodu değil', 'reference');
  for (const file of ['balanced-plate.webp','breakfast-bowl.webp','food-bulgur.webp','food-chicken.webp','food-salad.webp','meal-plate-wide.webp']) copy(fs.existsSync(path.join(repo,'apps/web/public/images',file)) ? path.join(repo,'apps/web/public/images',file) : path.join(root,'gorseller',file), `gorseller/${file}`, 'Mevcut web projesindeki yemek görseli; V3 fotoğrafının birebir bağımsız kaynağı değil', 'existing-web-asset');
  const html = fs.readFileSync(path.join(root,'referanslar/limely-karsilama.html'),'utf8');
  const keyframes = [...html.matchAll(/@keyframes\s+lm-[\w-]+\{[^\n]+/g)].map(x=>x[0]).join('\n');
  write('animasyonlar/orijinal-karakter-keyframes.css', `/* Özgün HTML içindeki .lm-character/.hand-right/.eye-right/.lm-leaf parçalarına aittir. Tek PNG üzerindeki eli ayrı hareket ettirmez. */\n${keyframes}\n`);
  write('animasyonlar/limely-motion.css', `.limely-mascot-float { animation: limely-float 1.5s ease-in-out 2; transform-origin: 50% 80%; }\n@keyframes limely-float { 0%,100% { transform:translateY(0) rotate(-2deg); } 50% { transform:translateY(-6px) rotate(1deg); } }\n@media (prefers-reduced-motion:reduce) { .limely-mascot-float { animation:none; } }\n`);
  write('tasarim/limely-tokens.json', JSON.stringify({ palette:manifest.palette, icon:{viewBox:24,strokeWidth:1.8,linecap:'round',linejoin:'round',pngPixels:96,displayPixels:24},spacing:[8,16,24,32],corners:{small:12,content:18,onboarding:24},typography:{onboarding:{headings:'Fredoka',body:'Figtree'},v3:{headings:'Manrope',body:'Inter'},note:'V3 fontları üretim talimatındaki yönü karşılar; raster görselin font metadata kaynağı yoktur.'},motion:{floatDurationMs:1500,repeat:2,respectReducedMotion:true} },null,2)+'\n');
  write('tasarim/limely-fonts.css', ['Fredoka','Figtree','Manrope','Inter'].map(name=>`@font-face{font-family:'${name}';src:url('../fontlar/${name.toLowerCase()}/${name.toLowerCase()}.ttf') format('truetype');font-weight:${name==='Fredoka'?'300 700':name==='Manrope'?'200 800':name==='Figtree'?'300 900':'100 900'};font-style:normal;font-display:swap;}`).join('\n')+"\n.limely-onboarding-heading{font-family:'Fredoka','Figtree',sans-serif}.limely-onboarding-body{font-family:'Figtree',sans-serif}.limely-v3-heading{font-family:'Manrope',sans-serif}.limely-v3-body{font-family:'Inter',sans-serif}\n");
  write('tasarim/limely-tokens.css', `:root{--limely-bg:#F8FAF2;--limely-ink:#203B2F;--limely-lime:#C9E879;--limely-sage:#83B977;--limely-leaf:#3D7756;--limely-yellow:#F5D96A;--limely-soft:#EAF3DE;--limely-icon-size:24px;--limely-radius:18px;}\n`);
  write('tasarim/ekran-varlik-eslestirmesi.json',JSON.stringify({
    'mobil-v3':{reference:'referanslar/limely-danisan-yeni-duzen-v3.png',logo:'logolar/limely-yazili-logo-renkli.svg',mascots:['maskotlar/limely-maskot-merhaba.svg','maskotlar/limely-maskot-su-molasi.svg'],icons:['bell','chevron-down','plus','calendar-days','chevron-right','house','calendar','chart-no-axes-column','message-circle','user-round'],components:['su-sisesi-az','enerji-gostergesi-ornek','aktif-sekme-cizgisi','bildirim-noktasi'],food:'gorseller/meal-plate-wide.webp',foodNote:'Mevcut web kaynağıdır. Referanstaki tam fotoğraf katmanı ayrı dosya halinde mevcut değil.'},
    'karsilama':{reference:'referanslar/limely-karsilama-ekranlari.png',html:'referanslar/limely-karsilama.html',mascots:['maskotlar/limely-maskot-merhaba.svg','maskotlar/limely-maskot-kutlama.svg','maskotlar/limely-maskot-olcum.svg'],icons:['arrow-left','sprout','body-scale','scale','dumbbell','shield-check','salad','info','calendar-days','height','armchair','walk','run','arrow-right','footprints','activity','pencil','rotate-ccw'],components:['secim-bos','secim-dolu','ilerleme-adimi-tamam','ilerleme-adimi-bekleyen']},
    'panel-v1-v2':{references:['referanslar/limely-panel.png','referanslar/limely-panel-tipografi-v2.png'],mascot:'maskotlar/limely-maskot-merhaba.svg',icons:['grid-2x2','users','utensils','calendar-days','package','messages-square','inbox','chart-column','smartphone','globe','settings','calendar-check','wallet','video','triangle-alert','bell','chevron-right'],decorations:['panel-koyu-banner','kart-kose-yesil','kart-kose-sari','kart-kose-pembe'],note:'Bu referanslar önceki sürümlerdir; yeni yerleşim için V3 kararı korunur.'},
    'panel-v3':{reference:'referanslar/limely-diyetisyen-yeni-duzen-v3.png',icons:['calendar','clipboard-check','scale','message-circle','layers','search','bell','plus','check','chevron-left','chevron-right','chevron-down','arrow-right']}
  },null,2)+'\n');
}

async function launcherMasters() {
  const icon = await sharp(path.join(root,'logolar/limely-simge-renkli.svg'),{density:144}).resize(760,760).png().toBuffer();
  fs.mkdirSync(path.join(root,'uygulama-ikonlari'),{recursive:true});
  await sharp({create:{width:1024,height:1024,channels:4,background:'#F8FAF2'}}).composite([{input:icon,left:132,top:132}]).png().toFile(path.join(root,'uygulama-ikonlari/ios-master-1024.png'));
  await sharp(path.join(root,'logolar/limely-simge-renkli.svg'),{density:144}).resize(260,260).extend({left:86,right:86,top:86,bottom:86,background:'#00000000'}).png().toFile(path.join(root,'uygulama-ikonlari/android-adaptive-foreground-432.png'));
  write('uygulama-ikonlari/android-background.xml','<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="limely_launcher_background">#F8FAF2</color></resources>\n');
}

async function main() {
  for (const [file,digest] of Object.entries(original)) if (hash(fs.readFileSync(path.join(root,file)))!==digest) throw new Error('Korunan varlık değişmiş: '+file);
  sourceFiles();
  await measurementMascot(); await icons(); await components(); await launcherMasters();
  const sourceRecords = JSON.parse(fs.readFileSync(path.join(__dirname,'dis-kaynaklar.json'),'utf8').replace(/^\uFEFF/,''));
  Object.assign(manifest,{version:'1.1.0',package:'Limely ortak web ve mobil görsel kaynak paketi',assets,files,dependencies:sourceRecords,protectedAssetHashes:'source/korunan-varliklar-sha256.json',screenMap:'tasarim/ekran-varlik-eslestirmesi.json',usage:'KULLANIM.txt',notes:['Önceki 20 logo/maskot dosyası byte düzeyinde korunur.','İkonlar 24 px Lucide çizimleri ve dört ekran uyarlamasıdır; PNG konseptlerinin kayıp vektör katmanları oldukları iddia edilmez.','Mezuralı maskot karşılama görselinden konturla vektörleştirildi.','Bağımsız V3 yemek fotoğrafı kaynağı mevcut değil; referans tam hali ve mevcut web yemek varlıkları eklendi.','Fontlar üretim talimatlarında belirtilen ailelerdir; kaynak PNG kesin font dosyası/ölçü bilgisi içermez.']});
  fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
  fs.copyFileSync(path.join(__dirname,'KULLANIM.template.txt'),path.join(root,'KULLANIM.txt'));
  console.log(JSON.stringify({assets:assets.length,icons:assets.filter(a=>a.category==='icon').length,mascots:5,files:files.length,version:manifest.version},null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
