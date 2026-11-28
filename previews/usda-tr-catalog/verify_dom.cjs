/* DOM and calculation checks; these do not establish visual/browser rendering. */
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
(async()=>{
 const {JSDOM,VirtualConsole}=await import('../../apps/web/node_modules/jsdom/lib/api.js');
 const errors=[];
 const virtualConsole=new VirtualConsole();
 virtualConsole.on('jsdomError',error=>errors.push(String(error)));
 const html=fs.readFileSync(path.join(__dirname,'index.html'),'utf8');
 const dom=new JSDOM(html,{runScripts:'dangerously',url:'file:///catalog/index.html',virtualConsole});
 const w=dom.window,d=w.document;
 // Browser-only scrolling/focus layout is outside this DOM test's scope.
 w.HTMLElement.prototype.scrollIntoView=function(){};
 const $=id=>d.getElementById(id),all=s=>[...d.querySelectorAll(s)];
 const fill=(id,text)=>{$(id).value=text;$(id).dispatchEvent(new w.Event('input',{bubbles:true}));};
 const select=(id,value)=>{$(id).value=value;$(id).dispatchEvent(new w.Event('change',{bubbles:true}));};
 const click=s=>{const e=d.querySelector(s);assert(e,'Missing element: '+s);e.click();};
 const calc=k=>d.querySelector(`#calculated [data-value="${k}"]`).textContent;
 const total=k=>d.querySelector(`#totals [data-value="${k}"]`).textContent;
 const checks=[],pass=s=>checks.push(s);
 assert($('load-error').hidden);assert.equal(all('#foods tr').length,45);
 for(const query of ['sızma zeytinyağı','SIZMA ZEYTINYAGI','zeytin yagi']){fill('search',query);assert(d.querySelector('[data-food="748608"]'));}
 fill('search','avakado');assert.equal(all('#foods tr').length,1);
 fill('search','CHICKEN breast');assert(all('#foods tr').length>=2);
 fill('search','ISPANAK');assert.equal(all('#foods tr').length,3);
 pass('gömülü veri açılışı; Türkçe/ascii/büyük harf, İngilizce ve eş anlamlı araması');
 fill('search','olmayanbesinxyz');assert.equal($('no-results').hidden,false);click('#reset-filters');
 click('#show-more');assert.equal(all('#foods tr').length,90);pass('sonuç yok, filtre temizleme, daha fazla göster');
 select('category','Baklagiller');assert(all('#foods tr').length>0);assert(all('#foods .food-select').every(b=>!/tavuk/i.test(b.textContent)));select('category','');
 fill('search','tavuk göğsü');select('preparation','Çiğ');assert(d.querySelector('[data-food="2646170"]'));assert(!d.querySelector('[data-food="331960"]'));
 select('preparation','Az suda pişmiş');click('[data-food="331960"]');assert.equal($('selected-preparation').textContent,'Az suda pişmiş');
 select('preparation','');click('[data-food="2646170"]');pass('besin grubu ve çiğ/pişmiş filtreleri');
 fill('quantity','150');assert.equal(calc('energyKcal'),'168');assert.equal(calc('proteinGrams'),'33,75');click('#add-item');assert.equal(all('.meal-item').length,1);
 pass('150 g tavuk = 168 kcal, 33,75 g protein; öğüne ekleme');
 for(const v of ['','0','-1','abc','Infinity','1.2.3','10000001']){fill('quantity',v);assert($('add-item').disabled);assert.equal($('amount-error').hidden,false);}
 fill('quantity','0,5');assert.equal(calc('energyKcal'),'0,56');fill('quantity','1.5');assert.equal(calc('energyKcal'),'1,68');pass('geçersiz miktarlar; kesirli virgül/nokta miktarları');
 fill('search','bulgur');click('[data-food="2710820"]');assert.equal($('portion').options.length,1);pass('kaynak ev ölçüsü olmayan besinde yalnız gram');
 const catalog=JSON.parse($('catalog-data').textContent);
 const food=catalog.foods.find(f=>f.portions.some(p=>p.source.foodPortion.measureUnit.name==='tablespoon'));
 const portion=food.portions.find(p=>p.source.foodPortion.measureUnit.name==='tablespoon');
 fill('search',food.nameTr);click(`[data-food="${food.fdcId}"]`);select('portion',portion.id);fill('quantity','0,5');
 const fmt=new Intl.NumberFormat('tr-TR',{maximumFractionDigits:2});
 assert.equal($('weight').textContent,`Toplam ${fmt.format(portion.gramWeight*.5)} g yenilebilir kısım`);click('#add-item');assert.equal(all('.meal-item').length,2);pass('USDA besine özgü yemek kaşığı; 0,5 porsiyon gram dönüşümü');
 click('[data-edit="1"]');fill('quantity','200');click('#add-item');
 assert(all('.meal-item')[0].textContent.includes('200 g'));
 assert.equal(total('energyKcal'),fmt.format(224+food.per100g.energyKcal*portion.gramWeight*.5/100));
 click('[data-remove="2"]');assert.equal(all('.meal-item').length,1);assert.equal(total('energyKcal'),'224');pass('öğün düzenleme/silme ve bağımsız iki besin toplamı');
 fill('search','sızma zeytinyağı');click('[data-food="748608"]');assert.equal($('missing-warning').hidden,false);
 const missing=catalog.foods.find(f=>f.fdcId===748608),key=Object.keys(missing.per100g).find(k=>missing.per100g[k]===null);
 assert.equal(calc(key),'—');click('#add-item');assert($('totals').textContent.includes('Kısmi'));assert($('total-note').textContent.includes('Kısmi toplam'));
 click('#clear-meal');assert.equal(all('.meal-item').length,0);click('#add-item');assert.equal(total(key),'—');pass('gerçek eksik makrolar ve kısmi/tümü eksik toplamlar; öğünü temizleme');
 click('#clear-meal');fill('search','tavuk kanat');click('[data-food="2727568"]');assert.equal(calc('carbsGrams'),'—');assert($('source-info').textContent.includes('-0.459'));
 pass('negatif USDA karbonhidratı kaynakta korunuyor; hesap değeri null');
 assert.equal(w.parseQuantity('0,5'),.5);assert.equal(w.parseQuantity('1.5'),1.5);
 assert.equal(errors.length,0,errors.join('\n'));pass('DOM/JavaScript hatası yok');
 const report={engine:'jsdom (gerçek tarayıcı/görsel doğrulama değildir)',passed:checks.length,checks,errors,
  notVerified:['Tarayıcıda file:// açılışı ve gerçek offline çalıştırma','Masaüstü/mobil görsel düzen','JSON indirme düğmesinin gerçek tarayıcı dosya indirmesi'],
  browserAttempt:'Bu görevde file:// açılışı tarayıcı URL güvenlik politikası tarafından engellendi. DOM testleri gerçek tarayıcı doğrulaması yerine geçmez.'};
 fs.writeFileSync(path.join(__dirname,'dom-verification.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));dom.window.close();
})().catch(error=>{console.error(error);process.exitCode=1;});
