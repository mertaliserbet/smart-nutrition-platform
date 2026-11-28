'use strict';
// No fetch, storage, API calls or external assets. All state is in this document.
const KEYS=['energyKcal','proteinGrams','carbsGrams','fatGrams'];
const LABELS=['Enerji · kcal','Protein · g','Karbonhidrat · g','Yağ · g'];
const fmt=new Intl.NumberFormat('tr-TR',{maximumFractionDigits:2});
const $=id=>document.getElementById(id);
const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const normalize=value=>String(value).toLocaleLowerCase('tr-TR').replace(/ı/g,'i').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,' ').trim();
const display=value=>value===null?'—':fmt.format(value);
function parseQuantity(text){const v=text.trim();if(!/^(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(v))return null;const n=Number(v.replace(',','.'));return Number.isFinite(n)&&n>0?n:null;}
function calculate(food,grams){return Object.fromEntries(KEYS.map(key=>[key,food.per100g[key]===null?null:grams/100*food.per100g[key]]));}
function summarize(items){return Object.fromEntries(KEYS.map(key=>{let sum=0,missing=0;for(const item of items){const v=calculate(item.food,item.grams)[key];if(v===null)missing++;else sum+=v;}return[key,{value:items.length&&missing===items.length?null:sum,missing}];}));}
function nutrientCards(values,totals=false){return KEYS.map((key,i)=>{const entry=totals?values[key]:{value:values[key],missing:0};return `<div class="nutrient ${i===0?'energy':''}"><b data-value="${key}">${display(entry.value)}</b><span>${LABELS[i]}</span>${entry.missing?`<span class="partial">Kısmi · ${entry.missing} kalem eksik</span>`:''}</div>`;}).join('');}
let catalog,byId,selected,categoryById,groupById,activeGroup='',editing=null,meal=[],nextItemId=1,limit=45;

function iconSvg(category){return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${category.svgBody}</svg>`;}
function iconBadge(id,size=''){
  const category=categoryById.get(id);
  if(!category)throw new Error(`Missing visual category: ${id}`);
  return `<span class="icon-badge ${size}" data-icon="${category.id}" style="--icon-bg:${category.background};--icon-color:${category.color}">${iconSvg(category)}</span>`;
}
function showView(view){
  for(const name of ['catalog','atlas']){
    const active=view===name;
    $(name+'-view').hidden=!active;
    $(name+'-tab').setAttribute('aria-selected',String(active));
    $(name+'-tab').tabIndex=active?0:-1;
  }
}
function renderGroups(){
  const groups=catalog.visualTaxonomy.groups;
  const button=(id,label,icon)=>`<button class="group-chip" type="button" data-group="${id}" aria-pressed="${activeGroup===id}">${icon}${esc(label)}</button>`;
  $('group-filters').innerHTML=button('','Tümü','')+groups.map(group=>{
    const sample=catalog.visualTaxonomy.categories.find(c=>c.groupId===group.id);
    return button(group.id,group.labelTr,iconSvg(sample));
  }).join('');
}
function renderAtlas(){
  const categories=catalog.visualTaxonomy.categories.filter(c=>!$('atlas-group').value||c.groupId===$('atlas-group').value);
  $('atlas-visible-count').textContent=`${categories.length} kategori · ${categories.filter(c=>c.isReserved).length} kategoride henüz besin yok`;
  $('icon-grid').innerHTML=categories.map(c=>{
    const examples=catalog.foods.filter(f=>f.visualCategoryId===c.id).slice(0,2).map(f=>f.nameTr.split(',')[0]);
    const subtitle=c.foodCount?examples.join(' · '):'Simge hazır. Bu katalogda henüz eşleşen kayıt yok.';
    return `<button type="button" class="icon-card ${c.isReserved?'reserved':''}" data-icon-category="${c.id}" aria-label="${esc(c.labelTr)}, ${c.foodCount} besin"><span class="card-top">${iconBadge(c.id,'large')}<span class="${c.isReserved?'reserved-label':'card-count'}">${c.isReserved?'İkon hazır':c.foodCount+' besin'}</span></span><h3>${esc(c.labelTr)}</h3><p>${esc(subtitle)}</p><span class="card-group">${esc(groupById.get(c.groupId).labelTr)}</span></button>`;
  }).join('');
}
function renderMappings(){
  const terms=normalize($('mapping-search').value).split(' ').filter(Boolean);
  const foods=catalog.foods.filter(f=>terms.every(term=>normalize(f.fdcId+' '+f.searchText).includes(term)));
  $('mapping-count').textContent=`${foods.length} / ${catalog.foods.length} besin`;
  $('mapping-rows').innerHTML=foods.map(f=>`<tr data-mapped-food="${f.fdcId}"><td>${iconBadge(f.visualCategoryId,'small')}</td><td><button class="mapping-food" data-atlas-food="${f.fdcId}">${esc(f.nameTr)}<span class="mapping-id">FDC ${f.fdcId} · ${esc(f.preparationTr)}</span></button></td><td>${esc(categoryById.get(f.visualCategoryId).labelTr)}</td><td>${esc(groupById.get(f.visualGroupId).labelTr)}</td></tr>`).join('')||'<tr><td colspan="4" class="empty">Eşleşme bulunamadı.</td></tr>';
}
function downloadText(name,text,type){
  const url=URL.createObjectURL(new Blob([text],{type}));
  const link=document.createElement('a');link.href=url;link.download=name;link.click();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function mappingExport(){return {previewOnly:true,groups:catalog.visualTaxonomy.groups,categories:catalog.visualTaxonomy.categories.map(({svgBody,...c})=>c),foods:catalog.foods.map(f=>({fdcId:f.fdcId,nameTr:f.nameTr,visualCategoryId:f.visualCategoryId,visualGroupId:f.visualGroupId}))};}
function bindVisualControls(){
  $('catalog-tab').addEventListener('click',()=>showView('catalog'));
  $('atlas-tab').addEventListener('click',()=>showView('atlas'));
  for(const name of ['catalog','atlas'])$(name+'-tab').addEventListener('keydown',event=>{
    if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
    event.preventDefault();const next=event.key==='Home'?'catalog':event.key==='End'?'atlas':name==='catalog'?'atlas':'catalog';
    showView(next);$(next+'-tab').focus();
  });
  $('group-filters').addEventListener('click',event=>{
    const button=event.target.closest('[data-group]');if(!button)return;
    activeGroup=button.dataset.group;$('icon-category').value='';limit=45;renderFoods();
  });
  $('icon-category').addEventListener('change',()=>{activeGroup='';limit=45;renderFoods();});
  $('atlas-group').addEventListener('change',renderAtlas);
  $('icon-grid').addEventListener('click',event=>{
    const card=event.target.closest('[data-icon-category]');if(!card)return;
    resetFilters();$('icon-category').value=card.dataset.iconCategory;renderFoods();showView('catalog');$('icon-category').focus();
  });
  $('mapping-search').addEventListener('input',renderMappings);
  $('mapping-rows').addEventListener('click',event=>{
    const button=event.target.closest('[data-atlas-food]');if(!button)return;
    const food=byId.get(Number(button.dataset.atlasFood));resetFilters();$('search').value=food.nameTr;
    chooseFood(food.fdcId);showView('catalog');$('detail-title').focus();
  });
  $('source-link').addEventListener('click',()=>{$('catalog-source').open=true;$('catalog-source').scrollIntoView({block:'start',behavior:'smooth'});});
  $('download-mapping').addEventListener('click',()=>downloadText('limely-besin-eslesmeleri.json',JSON.stringify(mappingExport(),null,2)+'\n','application/json;charset=utf-8'));
  $('download-taxonomy').addEventListener('click',()=>downloadText('icon-categories.json',JSON.stringify(catalog.visualTaxonomy,null,2)+'\n','application/json;charset=utf-8'));
  $('download-sprite').addEventListener('click',()=>{
    const symbols=catalog.visualTaxonomy.categories.map(c=>`<symbol id="limely-food-${c.id}" viewBox="0 0 24 24">${c.svgBody}</symbol>`).join('');
    downloadText('limely-food-sprite.svg',`<svg xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><defs>${symbols}</defs></svg>`,'image/svg+xml');
  });
}

function selectedPortion(){return selected.portions.find(p=>p.id===$('portion').value)||null;}
function currentGrams(){const n=parseQuantity($('quantity').value);if(n===null)return null;const grams=n*(selectedPortion()?.gramWeight??1);return Number.isFinite(grams)&&grams<=10000000?grams:null;}
function renderCalculation(){const grams=currentGrams();$('quantity').setAttribute('aria-invalid',String(grams===null));$('amount-error').hidden=grams!==null;$('amount-error').textContent='Sıfırdan büyük bir miktar gir. Ondalık için virgül veya nokta kullanabilirsin (0,5 gibi). Toplam en fazla 10.000.000 g olabilir.';$('add-item').disabled=grams===null;$('weight').innerHTML=grams===null?'Toplam ağırlık: —':`Toplam <strong>${fmt.format(grams)} g</strong> <span class="muted">yenilebilir kısım</span>`;$('calculated').innerHTML=nutrientCards(grams===null?Object.fromEntries(KEYS.map(k=>[k,null])):calculate(selected,grams));$('missing-warning').hidden=!KEYS.some(k=>selected.per100g[k]===null);}
function updatePortionNote(){const portion=selectedPortion();$('portion-note').textContent=portion?`Seçilen kaynak ölçüsü = ${fmt.format(portion.gramWeight)} g. Miktar bu ölçünün katıdır. USDA ölçüleri yerel kase/bardakla eşdeğer sayılmaz.`:(selected.portions.length?'Gram veya yalnız bu besine ait USDA ölçülerinden birini seç.':'Bu kayıt için kullanılabilir kaynaklı ev ölçüsü yok; yalnız gramla hesaplanır.');}
function chooseFood(id,item=null){selected=byId.get(Number(id));editing=item?.id??null;$('selected-icon').innerHTML=iconBadge(selected.visualCategoryId,'large');$('selected-category').textContent=categoryById.get(selected.visualCategoryId).labelTr;$('detail-title').textContent=selected.nameTr;$('original-name').textContent=selected.originalName;$('selected-preparation').textContent=selected.preparationTr;$('editor-mode').textContent=editing?'Öğün kalemini düzenle':'Miktarını belirle';$('portion').innerHTML='<option value="g">Gram (g)</option>'+selected.portions.map(p=>`<option value="${esc(p.id)}">${esc(p.labelTr)} · ${fmt.format(p.gramWeight)} g</option>`).join('');$('portion').value=item?.portionId??'g';$('quantity').value=item?String(item.quantity).replace('.',','):'100';$('add-item').textContent=editing?'Değişikliği kaydet':'Öğüne ekle';$('cancel-edit').hidden=!editing;updatePortionNote();renderCalculation();renderSource();renderFoods();}
function renderSource(){const s=selected.source;const mapping=KEYS.map((k,i)=>{const n=selected.nutrientMapping[k];return `<tr><td>${LABELS[i]}</td><td>${n?esc(n.nutrientId):'—'}</td><td>${n?esc(n.sourceAmount)+' '+esc(n.unit):'Eksik'}</td></tr>`;}).join('');const p=selectedPortion();$('source-info').innerHTML=`<dl><dt>Görsel kategori</dt><dd>${esc(categoryById.get(selected.visualCategoryId).labelTr)}</dd><dt>USDA grubu</dt><dd>${esc(selected.categoryTr)}</dd><dt>Veri kaynağı</dt><dd>USDA FoodData Central</dd><dt>FDC kimliği</dt><dd>${selected.fdcId}</dd><dt>Veri türü</dt><dd>${esc(s.dataType)}</dd><dt>Arşiv sürümü</dt><dd>${esc(s.releaseDate)}</dd><dt>Kayıt yayını</dt><dd>${esc(s.publicationDate??'Belirtilmemiş')}</dd><dt>Temel</dt><dd>Yenilebilir 100 g; sıvılarda da gram. ml dönüşümü yapılmaz.</dd></dl><table class="source-table" aria-label="USDA besin öğesi eşlemesi"><thead><tr><th>Besin öğesi</th><th>USDA ID</th><th>100 g kaynak değeri</th></tr></thead><tbody>${mapping}</tbody></table><p>Enerji: ${esc(selected.nutrientMapping.energyKcal?.name??'Kaynakta eksik')}. Kaynak enerjisi korunur; 4/4/9 hesabıyla değiştirilmez.</p>${p?`<p>Ölçü kaynağı: USDA foodPortion #${esc(p.id)}; ${esc(p.sourceAmount)} × ${esc(p.source.foodPortion.measureUnit.name)}; toplam ${fmt.format(p.gramWeight)} g. ${esc(p.source.foodPortion.modifier??p.source.foodPortion.portionDescription??'')}</p>`:''}<p><a href="${esc(s.url)}" target="_blank" rel="noopener noreferrer">USDA kaydını aç ↗</a> <small>(internet gerekir)</small></p><p>Negatif kaynak değerleri hesapta kullanılamaz olarak işaretlenir; kaynak değeri bu tabloda korunur.</p><p>Hesap: toplam gram ÷ 100 × kaynak değeri. Türkçe adlar editoryal çeviridir.</p>`;}

function filteredFoods(){
  const terms=normalize($('search').value).split(' ').filter(Boolean);
  return catalog.foods.filter(f=>(!activeGroup||f.visualGroupId===activeGroup)&&
    (!$('icon-category').value||f.visualCategoryId===$('icon-category').value)&&
    (!$('category').value||f.categoryTr===$('category').value)&&
    (!$('preparation').value||f.preparationTr===$('preparation').value)&&terms.every(term=>f.searchText.includes(term)));
}
function renderFoods(){
  const results=filteredFoods(),shown=results.slice(0,limit);renderGroups();
  $('result-count').textContent=`${results.length} besin`;
  $('shown-count').textContent=`${shown.length} / ${results.length} besin gösteriliyor`;
  $('show-more').hidden=shown.length>=results.length;$('no-results').hidden=results.length!==0;
  const reserved=categoryById.get($('icon-category').value)?.isReserved;
  document.querySelector('.detail-panel').hidden=Boolean(reserved);
  document.querySelector('.workspace').classList.toggle('empty-category',Boolean(reserved));
  $('empty-title').textContent=reserved?'Bu kategori için ikon hazır.':'Aramana uygun besin bulunamadı.';
  $('empty-note').textContent=reserved?'397 besin içinde bu türe ait doğrulanmış kayıt yok. Kataloğa örnek besin veya besin değeri eklenmedi.':'Başka bir ad dene veya filtreleri temizle.';
  $('foods').innerHTML=shown.map(f=>`<tr class="${f.fdcId===selected?.fdcId?'selected':''}"><td><button class="food-select" data-food="${f.fdcId}" aria-pressed="${f.fdcId===selected?.fdcId}">${iconBadge(f.visualCategoryId)}<span class="food-copy"><span class="food-name">${esc(f.nameTr)}</span><span class="preparation">${esc(f.preparationTr)} · ${esc(categoryById.get(f.visualCategoryId).labelTr)}</span></span></button></td>${KEYS.map((k,i)=>`<td><span class="cell-label">${LABELS[i]}</span>${display(f.per100g[k])}</td>`).join('')}</tr>`).join('');
}
function renderMeal(){const summary=summarize(meal);$('meal-count').textContent=`· ${meal.length} kalem`;$('clear-meal').disabled=!meal.length;$('meal-items').innerHTML=meal.length?meal.map(item=>{const vals=calculate(item.food,item.grams);const portion=item.food.portions.find(p=>p.id===item.portionId);return `<article class="meal-item">${iconBadge(item.food.visualCategoryId,'small')}<div><h3>${esc(item.food.nameTr)}</h3><p>${esc(item.food.preparationTr)}<br>${fmt.format(item.quantity)} ${portion?"× ":""}${esc(portion?.labelTr??'g')} ${portion?'= '+fmt.format(item.grams)+' g':''}<br>${display(vals.energyKcal)} kcal · P ${display(vals.proteinGrams)} g · K ${display(vals.carbsGrams)} g · Y ${display(vals.fatGrams)} g</p></div><div class="actions"><button data-edit="${item.id}" aria-label="${esc(item.food.nameTr)} miktarını düzenle">Düzenle</button><button data-remove="${item.id}" class="danger" aria-label="${esc(item.food.nameTr)} sil">Sil</button></div></article>`;}).join(''):'<div class="empty"><strong>Öğünün henüz boş.</strong>Katalogdan bir besin seçip miktarını ekle.</div>';$('totals').innerHTML=nutrientCards(summary,true);const missing=KEYS.some(k=>summary[k].missing);$('total-note').className=missing?'warning':'footnote';$('total-note').textContent=missing?'Kısmi toplam: eksik besin öğeleri sıfır sayılmaz. Her toplamın altındaki eksik kalem sayısını kontrol et.':'Miktarlar toplanırken yuvarlama yapılmaz; yalnız gösterilen değerler yuvarlanır.';}
function resetFilters(){activeGroup='';$('icon-category').value='';$('search').value='';$('category').value='';$('preparation').value='';limit=45;renderFoods();}
try{

  catalog=JSON.parse($('catalog-data').textContent);
  catalog.foods.sort((a,b)=>a.nameTr.localeCompare(b.nameTr,'tr'));
  categoryById=new Map(catalog.visualTaxonomy.categories.map(c=>[c.id,c]));
  groupById=new Map(catalog.visualTaxonomy.groups.map(g=>[g.id,g]));
  byId=new Map(catalog.foods.map(f=>[f.fdcId,f]));
  for(const food of catalog.foods){
    if(!categoryById.has(food.visualCategoryId))throw new Error(`Unmapped food ${food.fdcId}`);
    food.searchText=normalize([food.nameTr,food.originalName,...food.aliasesTr,food.preparationTr,categoryById.get(food.visualCategoryId).labelTr,groupById.get(food.visualGroupId).labelTr].join(' '));
  }
  $('catalog-meta').innerHTML=`<div><b>${catalog.foods.length}</b><span>Gerçek besin</span></div><div><b>${categoryById.size}</b><span>Özgün ikon kategorisi</span></div><div><b>${catalog.foods.length}/${catalog.foods.length}</b><span>Eşleştirilmiş kayıt</span></div>`;
  $('atlas-tab-count').textContent=String(categoryById.size);
  $('coverage-badge').textContent=`${catalog.foods.length} / ${catalog.foods.length} besin eşleşti`;
  $('icon-category').innerHTML='<option value="">Tüm ikon kategorileri</option>'+catalog.visualTaxonomy.categories.map(c=>`<option value="${c.id}">${esc(c.labelTr)} (${c.foodCount})</option>`).join('');
  for(const group of catalog.visualTaxonomy.groups){const option=document.createElement('option');option.value=group.id;option.textContent=group.labelTr;$('atlas-group').append(option);}
  for(const [id,key] of [['category','categoryTr'],['preparation','preparationTr']])for(const value of [...new Set(catalog.foods.map(f=>f[key]))].sort((a,b)=>a.localeCompare(b,'tr'))){const option=document.createElement('option');option.value=value;option.textContent=value;$(id).append(option);}
  $('catalog-info').innerHTML=`<p><strong>${catalog.stats.foodCount} gerçek besin</strong> · ${catalog.stats.foodsWithHouseholdPortions} besinde USDA kaynaklı ev ölçüsü · ${catalog.stats.foodsWithMissingValues} kayıtta en az bir enerji/makro değeri eksik veya kullanılamaz.</p><p>Kaynaklar: Foundation Foods <strong>29.10.2026</strong> ve SR Legacy <strong>Nisan 2018</strong>. Veri biçimi yalnız bu bağımsız önizlemeye aittir.</p><div class="link-row"><a href="${esc(catalog.source.downloadPage)}" target="_blank" rel="noopener noreferrer">Resmî indirmeler ↗</a><a href="${esc(catalog.source.documentationUrl)}" target="_blank" rel="noopener noreferrer">USDA veri açıklaması ↗</a><a href="${esc(catalog.source.licenseStatementUrl)}" target="_blank" rel="noopener noreferrer">USDA lisans beyanı ↗</a><a href="${esc(catalog.source.licenseUrl)}" target="_blank" rel="noopener noreferrer">CC0 1.0 ↗</a></div><p>USDA verileri kamu malıdır; CC0 1.0 Universal altında yayımlanır. Kaynak belirtilmiştir. USDA bu Türkçe çeviriyi veya ürünü onaylamış değildir.</p><p>${esc(catalog.source.citation)}</p><ul>${catalog.limitations.map(text=>`<li>${esc(text)}</li>`).join('')}</ul><p>Ev ölçüleri besine özeldir. “USDA cup” Türk tipi kase veya su bardağı olarak çevrilmez. RACC referans miktarları ev ölçüsü olarak sunulmaz. Kaynakta hazırlama belirtilmemişse pişmiş ya da çiğ olduğu varsayılmaz.</p><p>Enerji seçim sırası: kaynakta varsa 2048 (Atwater specific), sonra 2047 (Atwater general), sonra 1008. Protein 1003, karbonhidrat 1005 ve yağ 1004; birimler kcal/g olarak denetlenir. Karbonhidrat fark yöntemi lif içerebilir.</p><p>Görsel kategoriler bu önizleme için hazırlanmıştır. USDA grubu ve kaynak değerleri korunur. İkonlar özgün SVG çizimleridir; referans siteden kopyalanmamıştır. Manrope ve Inter fontları SIL Open Font License ile HTML içine gömülüdür; font lisansları teslim paketindedir.</p><button id="download-json">Kataloğu JSON olarak indir</button>`;
  chooseFood(2646170);renderMeal();renderAtlas();renderMappings();bindVisualControls();
  for(const id of ['search','category','preparation'])$(id).addEventListener(id==='search'?'input':'change',()=>{limit=45;renderFoods();});
  $('show-more').addEventListener('click',()=>{limit+=45;renderFoods();});$('reset-filters').addEventListener('click',resetFilters);
  $('foods').addEventListener('click',e=>{const button=e.target.closest('[data-food]');if(button)chooseFood(button.dataset.food);});
  $('quantity').addEventListener('input',renderCalculation);$('portion').addEventListener('change',()=>{$('quantity').value=$('portion').value==='g'?'100':'1';updatePortionNote();renderCalculation();renderSource();});
  $('portion-form').addEventListener('submit',e=>{e.preventDefault();const grams=currentGrams();if(grams===null){renderCalculation();return;}const item={id:editing??nextItemId++,food:selected,quantity:parseQuantity($('quantity').value),portionId:$('portion').value,grams};const wasEditing=editing!==null;if(wasEditing)meal=meal.map(old=>old.id===editing?item:old);else meal.push(item);$('live-status').textContent=selected.nameTr+(wasEditing?' güncellendi.':' öğüne eklendi.');chooseFood(selected.fdcId);renderMeal();});
  $('cancel-edit').addEventListener('click',()=>chooseFood(selected.fdcId));
  $('meal-items').addEventListener('click',e=>{const edit=e.target.closest('[data-edit]'),remove=e.target.closest('[data-remove]');if(edit){const item=meal.find(i=>i.id===Number(edit.dataset.edit));chooseFood(item.food.fdcId,item);$('detail-title').focus();$('detail-title').scrollIntoView({block:'center',behavior:'smooth'});}if(remove){const id=Number(remove.dataset.remove);meal=meal.filter(i=>i.id!==id);if(editing===id)chooseFood(selected.fdcId);renderMeal();$('live-status').textContent='Kalem öğünden silindi.';}});
  $('clear-meal').addEventListener('click',()=>{meal=[];chooseFood(selected.fdcId);renderMeal();$('live-status').textContent='Örnek öğün temizlendi.';});
  $('download-json').addEventListener('click',()=>{const data=JSON.parse($('catalog-data').textContent),blob=new Blob([JSON.stringify(data,null,2)+'\n'],{type:'application/json;charset=utf-8'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='catalog.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
}catch(error){$('load-error').hidden=false;console.error(error);}
