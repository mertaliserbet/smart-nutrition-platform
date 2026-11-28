/* Local file browser verification. No package installation or application startup.
 * Uses the repository's already installed Playwright only as a test tool.
 * Run: node previews/usda-tr-catalog/verify_browser.cjs
 */
const {chromium}=require('../../apps/web/node_modules/playwright');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const root=__dirname;
const catalog=JSON.parse(fs.readFileSync(path.join(root,'catalog.json'),'utf8'));
const foodById=new Map(catalog.foods.map(f=>[f.fdcId,f]));

(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const context=await browser.newContext({viewport:{width:1440,height:1000},locale:'tr-TR',offline:true});
 const page=await context.newPage();
 const errors=[],network=[];
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('request',r=>{if(/^https?:/.test(r.url()))network.push(r.url());});
 const checks=[];
 const pass=name=>checks.push(name);
 const url=pathToFileURL(path.join(root,'index.html')).href;
 await page.goto(url);
 assert.equal(await page.locator('#load-error').isVisible(),false);
 assert.equal(await page.locator('#foods tr').count(),45);
 pass('file:// çevrimdışı ilk açılış; gömülü veri; ilk 45 satır');
 for(const query of ['sızma zeytinyağı','SIZMA ZEYTINYAGI','zeytin yagi']){
  await page.locator('#search').fill(query);
  assert(await page.locator('[data-food="748608"]').count());
 }
 await page.locator('#search').fill('avakado');assert.equal(await page.locator('#foods tr').count(),1);
 await page.locator('#search').fill('CHICKEN breast');assert(await page.locator('#foods tr').count()>=2);
 await page.locator('#search').fill('ISPANAK');assert.equal(await page.locator('#foods tr').count(),3);
 pass('Türkçe/ascii/büyük harf, özgün İngilizce ad ve eş anlamlı araması');
 await page.locator('#search').fill('olmayanbesinxyz');assert(await page.locator('#no-results').isVisible());
 await page.locator('#reset-filters').click();assert.equal(await page.locator('#foods tr').count(),45);
 await page.locator('#show-more').click();assert.equal(await page.locator('#foods tr').count(),90);
 pass('sonuç yok, filtre temizleme, daha fazla göster');
 await page.locator('#search').fill('tavuk göğsü');
 await page.locator('#preparation').selectOption('Çiğ');assert(await page.locator('[data-food="2646170"]').count());
 assert.equal(await page.locator('[data-food="331960"]').count(),0);
 await page.locator('#preparation').selectOption('Az suda pişmiş');assert(await page.locator('[data-food="331960"]').count());
 await page.locator('[data-food="331960"]').click();
 assert.equal(await page.locator('#selected-preparation').textContent(),'Az suda pişmiş');
 pass('çiğ/az suda pişmiş ayrımı ve hazırlama filtresi');
 await page.locator('#preparation').selectOption('');
 await page.locator('[data-food="2646170"]').click();
 await page.locator('#quantity').fill('150');
 const value=async key=>(await page.locator(`#calculated [data-value="${key}"]`).textContent()).trim();
 assert.equal(await value('energyKcal'),'168');assert.equal(await value('proteinGrams'),'33,75');
 await page.locator('#add-item').click();assert.equal(await page.locator('.meal-item').count(),1);
 pass('150 g tavuk: 168 kcal / 33,75 g protein; öğüne ekleme');
 for(const input of ['0','-1','','abc','Infinity','1.2.3','10000001']){
  await page.locator('#quantity').fill(input);assert(await page.locator('#add-item').isDisabled());assert(await page.locator('#amount-error').isVisible());
 }
 await page.locator('#quantity').fill('0,5');assert.equal(await value('energyKcal'),'0,56');
 await page.locator('#quantity').fill('1.5');assert.equal(await value('energyKcal'),'1,68');
 pass('geçersiz miktarlar ve 0,5 / 1.5 g');
 await page.locator('#search').fill('bulgur');await page.locator('[data-food="2710820"]').click();
 assert.equal(await page.locator('#portion option').count(),1);pass('yalnız RACC olan besinde sadece gram');
 const portionFood=catalog.foods.find(f=>f.portions.some(p=>p.source.foodPortion.measureUnit.name==='tablespoon'));
 await page.locator('#search').fill(portionFood.nameTr);await page.locator(`[data-food="${portionFood.fdcId}"]`).click();
 const portion=portionFood.portions.find(p=>p.source.foodPortion.measureUnit.name==='tablespoon');
 await page.locator('#portion').selectOption(portion.id);await page.locator('#quantity').fill('0,5');
 assert.equal(await page.locator('#weight').textContent(),`Toplam ${new Intl.NumberFormat('tr-TR',{maximumFractionDigits:2}).format(portion.gramWeight*.5)} g yenilebilir kısım`);
 await page.locator('#add-item').click();assert.equal(await page.locator('.meal-item').count(),2);
 pass('besine özgü USDA yemek kaşığı, 0,5 kaynak porsiyonu ve gram hesabı');
 const first=page.locator('.meal-item').first();await first.getByRole('button',{name:/miktarını düzenle/}).click();
 await page.locator('#quantity').fill('200');await page.locator('#add-item').click();
 assert((await page.locator('.meal-item').first().textContent()).includes('200 g'));
 const expected=224+portionFood.per100g.energyKcal*portion.gramWeight*.5/100;
 const formatted=new Intl.NumberFormat('tr-TR',{maximumFractionDigits:2}).format(expected);
 assert.equal(await page.locator('#totals [data-value="energyKcal"]').textContent(),formatted);
 await page.locator('.meal-item').nth(1).getByRole('button',{name:/ sil$/}).click();assert.equal(await page.locator('.meal-item').count(),1);
 pass('kalem düzenleme/silme; iki besin toplamının bağımsız hesabı');
 const missingFood=catalog.foods.find(f=>f.fdcId===748608);
 assert(Object.values(missingFood.per100g).includes(null));
 await page.locator('#search').fill('sızma zeytinyağı');await page.locator('[data-food="748608"]').click();
 assert(await page.locator('#missing-warning').isVisible());
 const missingKey=Object.keys(missingFood.per100g).find(k=>missingFood.per100g[k]===null);
 assert.equal(await value(missingKey),'—');await page.locator('#add-item').click();
 assert((await page.locator('#totals').textContent()).includes('Kısmi'));
 assert((await page.locator('#total-note').textContent()).includes('Kısmi toplam'));
 pass('gerçek eksik makrolar: — ve besin öğesi bazında kısmi toplam');
 await page.locator('#clear-meal').click();assert.equal(await page.locator('.meal-item').count(),0);
 await page.locator('#add-item').click();assert((await page.locator('#totals').textContent()).includes('Kısmi'));
 assert.equal(await page.locator(`#totals [data-value="${missingKey}"]`).textContent(),'—');
 await page.reload();assert.equal(await page.locator('.meal-item').count(),0);
 pass('tüm değerler eksikse —; öğünü temizleme ve yenilemede geçici öğünün silinmesi');
 await page.locator('.source-detail summary').click();assert((await page.locator('#source-info').textContent()).includes('2646170'));
 await page.locator('#catalog-source summary').click();assert((await page.locator('#catalog-info').textContent()).includes('CC0 1.0'));
 await page.locator('#catalog-source summary').click();
 await page.locator('#search').fill('');
 await page.screenshot({path:path.join(root,'desktop.png'),fullPage:true});
 await page.setViewportSize({width:390,height:844});
 assert(await page.locator('#search').isVisible());
 assert(await page.locator('#portion').isVisible());
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
 await page.screenshot({path:path.join(root,'mobile.png'),fullPage:true});
 pass('1440 px masaüstü ve 390 px dar ekran; yatay taşma yok');
 assert.equal(errors.length,0,errors.join('\n'));assert.equal(network.length,0);
 pass('JavaScript hatası ve ağ isteği yok; testler tamamen offline');
 fs.writeFileSync(path.join(root,'browser-verification.json'),JSON.stringify({browser:'Microsoft Edge / Playwright',urlScheme:'file:',offline:true,checks,errors,network},null,2)+'\n');
 console.log(JSON.stringify({passed:checks.length,checks},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exitCode=1;});
