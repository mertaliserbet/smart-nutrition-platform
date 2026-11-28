/* All 397 assignments, category navigation, and icon rendering in the DOM. */
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
(async()=>{
 const {JSDOM,VirtualConsole}=await import('../../apps/web/node_modules/jsdom/lib/api.js');
 const errors=[],virtualConsole=new VirtualConsole();virtualConsole.on('jsdomError',e=>errors.push(String(e)));
 const dom=new JSDOM(fs.readFileSync(path.join(__dirname,'index.html'),'utf8'),{runScripts:'dangerously',url:'file:///catalog/index.html',virtualConsole});
 const w=dom.window,d=w.document;w.HTMLElement.prototype.scrollIntoView=function(){};
 const $=id=>d.getElementById(id),all=selector=>[...d.querySelectorAll(selector)];
 const click=selector=>{const e=d.querySelector(selector);assert(e,selector);e.click();};
 const select=(id,value)=>{$(id).value=value;$(id).dispatchEvent(new w.Event('change',{bubbles:true}));};
 const catalog=JSON.parse($('catalog-data').textContent),categories=catalog.visualTaxonomy.categories;
 const counts=new Map(categories.map(c=>[c.id,0]));
 assert.equal(catalog.foods.length,397);assert.equal(categories.length,36);
 assert.equal(new Set(categories.map(c=>c.svgBody)).size,36,'Every category needs a distinct drawing');
 for(const food of catalog.foods){assert(counts.has(food.visualCategoryId));counts.set(food.visualCategoryId,counts.get(food.visualCategoryId)+1);}
 for(const c of categories){assert.equal(c.foodCount,counts.get(c.id));assert.equal(c.isReserved,c.foodCount===0);}
 assert.deepEqual(categories.filter(c=>c.isReserved).map(c=>c.id).sort(),['protein-drinks','smoothies','water']);
 assert.equal(all('#mapping-rows tr').length,397);assert.equal(all('#icon-grid .icon-card').length,36);
 click('#atlas-tab');assert.equal($('atlas-view').hidden,false);assert.equal($('catalog-view').hidden,true);
 $('atlas-tab').dispatchEvent(new w.KeyboardEvent('keydown',{key:'ArrowLeft',bubbles:true}));assert.equal($('catalog-view').hidden,false);
 click('#atlas-tab');select('atlas-group','drinks');assert.equal(all('#icon-grid .icon-card').length,6);select('atlas-group','');
 let checkedRows=0;
 for(const category of categories){
   click('#atlas-tab');click(`[data-icon-category="${category.id}"]`);
   assert.equal($('catalog-view').hidden,false);
   while(!$('show-more').hidden)click('#show-more');
   const rows=all('#foods tr');assert.equal(rows.length,category.foodCount,category.id);
   for(const row of rows){
     const food=catalog.foods.find(f=>f.fdcId===Number(row.querySelector('[data-food]').dataset.food));
     assert.equal(food.visualCategoryId,category.id);
     assert.equal(row.querySelector('.icon-badge').dataset.icon,category.id);
     assert(row.querySelector('.icon-badge svg path, .icon-badge svg circle'));
     checkedRows++;
   }
   if(category.isReserved){assert.equal($('no-results').hidden,false);assert(d.querySelector('.detail-panel').hidden);}
 }
 assert.equal(checkedRows,397);
 const specific={2346400:'vegetables',321611:'vegetables',2515376:'nuts',2758989:'spreads',2261420:'flour',174288:'flour',1999630:'plant-drinks',2257046:'plant-drinks',2710819:'seeds',171330:'seeds',790508:'oils',2346385:'cheese',2758990:'milk',2758988:'sauces',2747664:'leafy-greens',2710826:'grains',171970:'seafood',175168:'fish'};
 for(const [fdcId,category] of Object.entries(specific))assert.equal(catalog.foods.find(f=>f.fdcId===Number(fdcId)).visualCategoryId,category);
 click('#atlas-tab');$('mapping-search').value='2646170';$('mapping-search').dispatchEvent(new w.Event('input',{bubbles:true}));
 assert.equal(all('#mapping-rows tr').length,1);click('[data-atlas-food="2646170"]');
 assert.equal($('detail-title').textContent,'Tavuk göğsü, derisiz, kemiksiz');assert.equal(d.querySelector('#selected-icon .icon-badge').dataset.icon,'poultry');
 click('#add-item');assert.equal(d.querySelector('.meal-item .icon-badge').dataset.icon,'poultry');
 click('[data-edit="1"]');assert.equal(d.querySelector('#selected-icon .icon-badge').dataset.icon,'poultry');
 click('#source-link');assert($('catalog-source').open);
 assert.equal(errors.length,0,errors.join('\n'));
 const report={engine:'jsdom',assignedFoods:397,renderedAndFilteredFoods:checkedRows,uniqueSvgIcons:36,activeCategories:33,reservedCategories:3,
  checks:['397 benzersiz kaynak kimliği, her birine tam bir ikon kategorisi','36 kategorinin her birinde filtrelenen satırların ve gerçek SVG ikonlarının tek tek kontrolü','İkon atlası, klavye sekmeleri, grup filtresi, FDC ile eşleşme araması','Besin seçimi, ayrıntı, öğün ve düzenlemede aynı ikon','Taze fasulye, soya içeceği, fıstık, un, krema/peynir, sos ve balık/deniz ürünü ayrımları','Boş kategorilerde sahte kayıt yok; ayrıntı paneli gizli','Kaynak ayrıntısına erişim'],errors,
  limitations:['DOM doğrulaması gerçek tarayıcıda görsel düzen doğrulaması değildir.','file:// tarayıcı açılışı URL güvenlik politikası tarafından engellendi.']};
 fs.writeFileSync(path.join(__dirname,'icon-verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));dom.window.close();
})().catch(e=>{console.error(e);process.exitCode=1;});
