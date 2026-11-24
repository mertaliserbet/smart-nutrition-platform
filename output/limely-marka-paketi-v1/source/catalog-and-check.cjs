const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
let sharp;try{sharp=require('sharp')}catch{sharp=require('C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1123-915-0_26.1123.915.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules/sharp')}
const root=path.resolve(__dirname,'..');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'asset-manifest.json'),'utf8'));
const esc=t=>String(t).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function hasGlyph(bytes, cp) {
  let cmap=0;
  for(let i=0;i<bytes.readUInt16BE(4);i++){const p=12+i*16;if(bytes.toString('ascii',p,p+4)==='cmap')cmap=bytes.readUInt32BE(p+8)}
  assert(cmap,'Font cmap missing');
  for(let i=0;i<bytes.readUInt16BE(cmap+2);i++){
    const p=cmap+bytes.readUInt32BE(cmap+4+i*8+4),format=bytes.readUInt16BE(p);
    if(format===12){for(let j=0;j<bytes.readUInt32BE(p+12);j++){const g=p+16+j*12,start=bytes.readUInt32BE(g),end=bytes.readUInt32BE(g+4);if(cp>=start&&cp<=end&&bytes.readUInt32BE(g+8)+cp-start>0)return true}}
    if(format===4&&cp<=65535){const n=bytes.readUInt16BE(p+6)/2,end=p+14,start=end+2*n+2,delta=start+2*n,ranges=delta+2*n;for(let j=0;j<n;j++){if(cp<bytes.readUInt16BE(start+2*j)||cp>bytes.readUInt16BE(end+2*j))continue;const off=bytes.readUInt16BE(ranges+2*j),d=bytes.readInt16BE(delta+2*j);let glyph=off?bytes.readUInt16BE(ranges+2*j+off+2*(cp-bytes.readUInt16BE(start+2*j))):cp;if(off&&glyph===0)continue;if(((glyph+d)&65535)>0)return true}}
  }
  return false;
}
const labels={icon:'İkonlar — koyu ve beyaz',mascot:'Maskotlar',component:'Su, seçim ve ilerleme',decoration:'Dekorlar',brand:'Korunan logo ve maskotlar'};
const fontNames=['Fredoka','Figtree','Manrope','Inter'];
async function main(){
  let html=`<!doctype html><html lang="tr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Limely ortak görsel kaynak kataloğu</title><link rel="stylesheet" href="tasarim/limely-fonts.css"><style>*{box-sizing:border-box}body{margin:0;background:#F8FAF2;color:#203B2F;font:16px Inter,Arial,sans-serif}main{max-width:1450px;margin:auto;padding:32px}h1,h2{font-family:Manrope,Arial,sans-serif}h1{font-size:32px}p{line-height:1.6}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:16px}.asset{padding:16px;background:white;border:1px solid #e2e9db;border-radius:16px;min-width:0}.asset img{width:100%;height:110px;object-fit:contain}.asset.dark{background:#203B2F;color:white}.name{overflow-wrap:anywhere;font-size:12px}a{color:inherit}.links{display:flex;gap:16px}.asset.icon img{height:40px;margin:15px 0}.swatches{display:flex;flex-wrap:wrap;gap:16px}.swatch{padding:20px;border:1px solid #d1dbc9;border-radius:12px}.font-sample{background:white;padding:20px;border-radius:16px;margin-bottom:12px}section{margin:36px 0}code{overflow-wrap:anywhere}.reference img{height:200px}</style><main><h1>Limely · ortak görsel kaynak paketi</h1><p>Mert / Flutter ve Uğur / React için aynı sabit dosyalar. ${manifest.assets.length} SVG + ${manifest.assets.length} PNG; 60 ikonun iki renk karşılığı; 5 maskot pozu. <a href="KULLANIM.txt">Kullanım TXT</a> · <a href="asset-manifest.json">Dosya listesi</a> · <a href="tasarim/ekran-varlik-eslestirmesi.json">Ekran eşleştirmesi</a></p>`;
  for(const category of ['brand','mascot','icon','component','decoration']){
    html+=`<section><h2>${labels[category]}</h2><div class="grid">`;
    for(const a of manifest.assets.filter(a=>(a.category||'brand')===category)) html+=`<article class="asset ${category==='icon'?'icon':''} ${a.svg.includes('/beyaz/')||a.svg.includes('-beyaz.svg')?'dark':''}"><img src="${esc(a.svg)}" alt="${esc(a.title)}"><p class="name">${esc(a.title)}</p><p class="name">${esc(a.svg)}</p><div class="links"><a href="${esc(a.svg)}">SVG</a><a href="${esc(a.png)}">PNG</a></div></article>`;
    html+='</div></section>';
  }
  html+='<section><h2>Yemek kaynakları — mevcut web dosyaları</h2><p>V3 fotoğrafının ayrı orijinali mevcut değil. Buradaki dosyalar mevcut web uygulamasındandır; özgün ekran referansı aşağıdadır.</p><div class="grid">';
  for(const f of manifest.files.filter(f=>f.file.startsWith('gorseller/'))) html+=`<article class="asset"><img src="${esc(f.file)}" alt="Yemek kaynak görseli"><a class="name" href="${esc(f.file)}">${esc(f.file)}</a></article>`;
  html+='</div></section><section><h2>Fontlar ve Türkçe karakter örneği</h2>';
  for(const font of fontNames) html+=`<div class="font-sample" style="font-family:'${font}',Figtree,sans-serif"><strong>${font}</strong><p style="font-size:26px">Günün, senin ritminde. Çç Ğğ Iı İi Öö Şş Üü · 0123456789</p>${font==='Fredoka'?'<p>Ğ/ğ/İ/Ş/ş kaynakta yoktur; bu harfler Figtree yedeğiyle gösterilir. Logo yazısı vektördür ve etkilenmez.</p>':''}<a href="fontlar/${font.toLowerCase()}/OFL.txt">OFL lisansı</a></div>`;
  html+='</section><section><h2>Renkler</h2><div class="swatches">';
  for(const [name,color]of Object.entries(manifest.palette))html+=`<div class="swatch" style="background:${color};color:${name==='ink'||name==='leaf'?'white':'#203B2F'}">${name}<br>${color}</div>`;
  html+='</div></section><section><h2>Özgün tasarım kaynakları</h2><p>V1/V2 kaynakları görsel referanstır; yeni yerleşimde V3 yönü korunur.</p><div class="grid">';
  for(const f of manifest.files.filter(f=>f.file.endsWith('.png')&&f.file.startsWith('referanslar/')))html+=`<article class="asset reference"><a href="${esc(f.file)}"><img src="${esc(f.file)}" alt="${esc(f.file)}"><span class="name">${esc(f.file)}</span></a></article>`;
  html+='</div></section><p>Özgün HTML, animasyon CSS kaynakları, platform ikon master dosyaları, lisanslar ve doğrulama kayıtları pakettedir. Gerçek cihaz testi bu katalogla yapılmış sayılmaz.</p></main></html>';
  fs.writeFileSync(path.join(root,'KATALOG.html'),html+'\n');
  for(const m of html.matchAll(/(?:src|href)="([^"]+)"/g))assert(fs.existsSync(path.join(root,m[1])),`Broken catalog reference: ${m[1]}`);
  for(const f of manifest.files)assert.equal(hash(fs.readFileSync(path.join(root,f.file))),f.sha256,`Source changed ${f.file}`);
  for(const f of manifest.dependencies.files)assert.equal(hash(fs.readFileSync(path.join(root,f.file))),f.sha256,`Dependency changed ${f.file}`);
  const fontCoverage=[];
  for(const fontFile of manifest.dependencies.files.filter(f=>f.file.endsWith('.ttf'))){
    const bytes=fs.readFileSync(path.join(root,fontFile.file));
    assert(bytes.readUInt32BE(0)===0x00010000||bytes.toString('ascii',0,4)==='OTTO',`Invalid font: ${fontFile.file}`);
    const missing=[...'ÇçĞğIıİiÖöŞşÜü'].filter(char=>!hasGlyph(bytes,char.codePointAt(0)));
    assert.deepEqual(missing,fontFile.file.includes('/fredoka/')?['Ğ','ğ','İ','Ş','ş']:[],`Unexpected font coverage: ${fontFile.file}`);
    fontCoverage.push({file:fontFile.file,testCharacters:'ÇçĞğIıİiÖöŞşÜü',missing,fallback:missing.length?'Figtree':null});
  }
  fs.writeFileSync(path.join(root,'fontlar/turkce-karakter-kontrolu.json'),JSON.stringify(fontCoverage,null,2)+'\n');
  const ios=await sharp(path.join(root,'uygulama-ikonlari/ios-master-1024.png')).stats();assert(ios.isOpaque,'iOS master must be opaque');
  const W=1600,H=1620;
  const text=(str,x,y,size=20)=>`<text x="${x}" y="${y}" font-size="${size}" font-family="Segoe UI,Arial,sans-serif" fill="#203B2F">${esc(str)}</text>`;
  let bg=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="100%" height="100%" fill="#F8FAF2"/>${text('LIMELY · WEB + MOBİL ORTAK GÖRSEL PAKETİ',50,60,32)}${text('Korunan logo ve maskotlar · 60 ikon · kaynaklar · fontlar · Flutter / React kullanım notları',50,100)}<rect x="40" y="128" width="1520" height="220" rx="22" fill="white"/>${text('Beş sabit maskot pozu',50,390,26)}`;
  const comp=[];
  async function image(file,w,h,x,y){comp.push({input:await sharp(path.join(root,file),{density:200}).resize(w,h,{fit:'contain',background:'#00000000'}).png().toBuffer(),left:x,top:y})}
  await image('logolar/limely-yazili-logo-renkli.svg',720,200,70,137);
  await image('bilesenler/su-sisesi-az.svg',80,140,1000,160);
  await image('bilesenler/su-bardagi-dolu.svg',70,110,1110,180);
  await image('bilesenler/secim-dolu.svg',56,56,1240,205);
  const poses=['merhaba','goz-kirpma','su-molasi','kutlama','olcum'];
  for(let i=0;i<poses.length;i++){
    bg+=`<rect x="${40+i*306}" y="410" width="294" height="300" rx="20" fill="white"/>${text(['Merhaba','Göz kırpma','Su molası','Kutlama','Ölçüm'][i],65+i*306,690,19)}`;
    await image(`maskotlar/limely-maskot-${poses[i]}.svg`,275,265,49+i*306,420);
  }
  bg+=text('60 ortak ikon · 24 px çizim kutusu · SVG + PNG · koyu / beyaz',50,765,26);
  const names=manifest.assets.filter(a=>a.category==='icon'&&a.svg.includes('/koyu/'));
  for(let i=0;i<names.length;i++){
    const x=42+(i%10)*153,y=795+Math.floor(i/10)*104;
    bg+=`<rect x="${x}" y="${y}" width="141" height="94" rx="12" fill="white"/>${text(path.basename(names[i].svg,'.svg'),x+5,y+79,11)}`;
    await image(names[i].svg,34,34,x+54,y+15);
  }
  bg+=text('Fontlar: Fredoka · Figtree · Manrope · Inter',50,1460,23);
  bg+=text('TXT: Mert için Flutter / PNG / SVG · Uğur için React / yerel fontlar / dosya eşleştirmeleri',50,1502,21);
  bg+=text('Tüm varlıklar ve özgün ekranlar KATALOG.html içinde. İlk 20 logo/maskot dosyası korundu.',50,1543,20);
  bg+='</svg>';
  await sharp(Buffer.from(bg)).composite(comp).png().toFile(path.join(root,'limely-genisletilmis-paket.png'));
  console.log(JSON.stringify({catalogReferencesValid:true,sourceFilesVerified:manifest.files.length,dependenciesVerified:manifest.dependencies.files.length,fonts:4,preview:'limely-genisletilmis-paket.png'},null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1});
