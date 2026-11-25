'use strict';

// Presentation data only: deliberately independent of API DTOs and persistent storage.
const asset = 'varliklar/';
const iconMap = Object.freeze({ grid:'grid-2x2',users:'users',meal:'salad',plan:'clipboard-list',calendar:'calendar-days',message:'messages-square',chart:'chart-column',settings:'settings',chevron:'chevron-down',left:'chevron-left',right:'chevron-right',arrow:'arrow-right',back:'arrow-left',bell:'bell',plus:'plus',search:'search',layers:'layers',clock:'clock',check:'check',checked:'circle-check',user:'user-round',shield:'shield-check',menu:'menu',close:'x',utensils:'utensils',edit:'pencil',info:'info',leaf:'leaf',note:'notebook-pen',refresh:'rotate-ccw' });
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = (name, inverse = false) => iconMap[name] ? `<img class="icon" src="${asset}ikonlar/${inverse ? 'beyaz' : 'koyu'}/${iconMap[name]}.svg" alt="" width="24" height="24" aria-hidden="true">` : '';
const fields=window.LimelyFields;
fields.configure(icon);
const logo = () => `<img class="logo" src="${asset}logolar/limely-yazili-logo-renkli.svg" alt="Limely" width="202" height="73">`;
const food = (name, cls = 'food-thumb') => `<img class="${cls}" src="${asset}gorseller/${name}.webp" alt="" width="92" height="92">`;
const initials = name => name.split(' ').slice(0,2).map(s => s[0]).join('').toLocaleUpperCase('tr-TR');
const names = ['Elif Yılmaz','Kerem Kaya','Gizem Arslan','Murat Aksoy','Deniz Aydın','Ece Demir','İpek Çelik','Öykü Şen','Çağla Yıldız','Şule Acar','Işık Güneş','Oğuz Eren','Duru Yalçın','Arda Ekin','Bora Deniz','Aylin Koç'];
const goals = ['Dengeli beslenme','Kilo verme','Kilo verme','Kiloyu koruma','Kilo alma','Dengeli beslenme'];
const planNames = ['Dengeli Başlangıç','Aktif Yaşam','Haftalık Denge','Koruma Programı','Güç ve Beslenme','Henüz atanmadı'];
const statuses = ['Güncel','Güncel','Plan güncellenecek','Ölçüm bekleniyor','Güncel','Program bekliyor'];
const samples = names.map((name,i) => ({ key:i, name, email:`ornek${i+1}@example.test`, goal:goals[i%6], measurement:i===5?'Yeni kayıt':`${[24,23,20,18,22,24][i%6]} Kasım · ${[72,86,78,80,62,70][i%6]} kg`, plan:planNames[i%6], state:statuses[i%6], waiting:i===2||i===3||i===5 }));
const programs = [
  {key:0,title:'Dengeli Başlangıç',tag:'Dengeli beslenme',days:7,kcal:1700,photo:'breakfast-bowl'},
  {key:1,title:'Aktif Yaşam',tag:'Spor ve beslenme',days:7,kcal:2100,photo:'balanced-plate'},
  {key:2,title:'Haftalık Denge',tag:'Kilo yönetimi',days:7,kcal:1800,photo:'food-salad'},
  {key:3,title:'Koruma Programı',tag:'Kiloyu koruma',days:14,kcal:2000,photo:'food-chicken'}
];
const navItems = [['Genel bakış','grid','overview'],['Danışanlar','users','danisanlar'],['Öğün incelemeleri','meal','meals',6],['Programlar','plan','programlar'],['Randevular','calendar','appointments'],['Mesajlar','message','messages',2],['Raporlar','chart','reports']];
let currentPage = '';
let clientState = {tab:'all',query:'',goal:'',status:'',measurement:'',page:1};
let planState = {tab:'templates',query:'',goal:'',duration:'',selected:0,panel:true,client:0,start:'2026-11-25',durationValue:'7',kcal:'1700',day:0,editFirst:true};
let draft = null;
let modalReturnFocus = null;
let toastTimer;
const app = document.getElementById('app');
const modal = document.getElementById('modal');

function notify(message) {
  const node = document.getElementById('toast');
  clearTimeout(toastTimer); node.textContent=message; node.hidden=false;
  toastTimer=setTimeout(()=>{node.hidden=true;},6000);
}
function openModal(title, content, cls='') {
  fields.closeAll();
  modalReturnFocus=document.activeElement;
  modal.className=cls;
  document.getElementById('modal-content').innerHTML=`<div class="modal-header"><h2 id="modal-title">${escapeHtml(title)}</h2><button class="icon-button" type="button" data-action="close-modal" aria-label="Pencereyi kapat">${icon('close')}</button></div><div class="modal-body">${content}</div>`;
  modal.showModal();
}
function closeModal() { fields.closeAll(); modal.close(); }
modal.addEventListener('close',()=>{if(modalReturnFocus?.isConnected)modalReturnFocus.focus();});
modal.addEventListener('click',event=>{if(event.target===modal){const r=modal.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)closeModal();}});
function info(title, message) { openModal(title,`<p>${escapeHtml(message)}</p><div class="inline-note">${icon('info')}<span>Bu çalışma etkileşimli tasarım önizlemesidir. Tüm kişi ve kayıtlar sentetiktir.</span></div><button class="button button-primary" data-action="close-modal">Tamam</button>`); }
function notificationMenu() {
  return `<details class="notifications"><summary class="icon-button" aria-label="Örnek bildirimleri aç">${icon('bell')}<span class="notification-dot" aria-hidden="true"></span></summary><div class="popover"><strong>Örnek bildirimler</strong><p>3 program gözden geçirilmeyi bekliyor.</p><button data-action="go-programs">Programları görüntüle ${icon('arrow')}</button><p>Yalnız sentetik önizleme; bildirim teslimi yapılmaz.</p></div></details>`;
}
function sidebar(page) {
  return `<aside class="sidebar"><div class="sidebar-brand"><a href="#danisanlar" aria-label="Limely önizleme ana paneli">${logo()}<span class="role-label">DİYETİSYEN</span></a><button class="icon-button mobile-menu" data-action="toggle-menu" aria-label="Menüyü aç" aria-expanded="false" aria-controls="side-navigation">${icon('menu')}</button></div><div class="sidebar-content" id="side-navigation"><nav class="side-nav" aria-label="Diyetisyen çalışma alanı">${navItems.map(([label,key,route,count])=>['danisanlar','programlar'].includes(route)?`<a href="#${route}" class="side-link ${page===route?'active':''}" ${page===route?'aria-current="page"':''}>${icon(key,page===route)}<span>${label}</span>${count?`<span class="badge-count">${count}</span>`:''}</a>`:`<button class="side-link" data-action="scope" data-label="${label}">${icon(key)}<span>${label}</span>${count?`<span class="badge-count">${count}</span>`:''}</button>`).join('')}</nav><div class="side-bottom"><div class="settings-link"><button class="side-link" data-action="scope" data-label="Ayarlar">${icon('settings')}Ayarlar</button></div><details class="profile-menu"><summary><span class="avatar" aria-hidden="true">DA</span><span>Dyt. Defne Akarsu</span>${icon('chevron')}</summary><div class="popover"><p>Sentetik diyetisyen profili</p><button data-action="scope" data-label="Hesabım">Hesabım</button><button data-action="invite">Bağlantılar ve davet</button><a href="#giris">Giriş önizlemesine dön</a></div></details></div></div></aside>`;
}
function shell(page,html) {
  return `<div class="preview-stage workspace">${sidebar(page)}<main id="main-content" class="workspace-main">${html}</main></div>`;
}
function selectControl(label,key,value,options,iconName='layers',scope='clients') {
  return `<div class="filter-control">${icon(iconName)}${fields.select({label,id:`${scope}-${key}`,value,options,attributes:`data-filter="${key}" data-scope="${scope}"`})}</div>`;
}
function header(title,description,actions='') {
  return `<header class="page-header"><div><h1 tabindex="-1">${title}</h1><p class="page-description">${description}</p></div><div class="header-actions">${actions}</div></header>`;
}
function loginPage() {
  return `<div class="preview-stage auth-stage"><div class="auth-shell"><header class="auth-header"><a href="#giris" aria-label="Limely giriş önizlemesi">${logo()}</a><button class="text-button" data-action="scope" data-label="Tanıtım sayfaları">Ana sayfaya dön ${icon('arrow')}</button></header><main id="main-content" class="auth-content"><h1 tabindex="-1">Tekrar hoş geldin</h1><p class="auth-description">Günlüğüne ve planına kaldığın yerden devam et.</p><form class="auth-form" id="login-form" novalidate><div class="login-error" id="login-error" role="alert" hidden></div><label for="login-email">E-posta</label><div class="input-wrap"><input id="login-email" type="email" inputmode="email" autocomplete="off" placeholder="ornek@eposta.com" aria-describedby="login-help" required></div><label for="login-password">Şifre</label><div class="input-wrap"><input id="login-password" type="password" autocomplete="off" placeholder="••••••••" minlength="8" required aria-describedby="login-help"><button class="password-toggle" type="button" data-action="toggle-password" aria-controls="login-password" aria-pressed="false">Göster</button></div><div class="login-options"><label class="check-label"><input type="checkbox" disabled title="Kalıcı oturum mevcut web sözleşmesinde desteklenmiyor.">Beni hatırla</label><button class="text-button" type="button" data-action="reset-preview">Şifremi unuttum</button></div><button class="button button-primary auth-submit" type="submit">Giriş yap</button><div class="divider">Hesabın yok mu?</div><button class="register-link" type="button" data-action="apply-preview">Hesap oluştur</button></form><p class="auth-synthetic" id="login-help">Önizleme · Örnek e-posta ve en az 8 karakter kullanabilirsin.</p></main><div class="auth-encouragement" aria-hidden="true"><img src="${asset}maskotlar/limely-maskot-merhaba.svg" alt="" width="210" height="170"><p>Küçük adımlar,<br>düzenli takip.</p></div><footer class="auth-footer"><button data-action="legal" data-label="Gizlilik">Gizlilik</button> · <button data-action="legal" data-label="Kullanım koşulları">Kullanım koşulları</button></footer></div></div>`;
}
function clientsPage() {
  const s=clientState;
  return shell('danisanlar',header('Danışanlar','Danışanlarını ve takip süreçlerini tek yerden yönet.',`<label class="search-control header-search">${icon('search')}<span class="sr-only">Danışan ara</span><input type="search" id="client-search" placeholder="Ad, e-posta veya telefon ara" value="${escapeHtml(s.query)}" autocomplete="off"></label>${notificationMenu()}<button class="button button-primary" data-action="invite">${icon('plus')}Danışan ekle</button>`)+`<div class="summary-strip"><span>${icon('users')}<span><strong>16</strong> aktif danışan</span></span><span>${icon('calendar')}<span><strong>3</strong> takip bekliyor</span></span><span>${icon('user')}<span><strong>2</strong> yeni kayıt</span></span><span class="sample-label">Örnek veriler</span></div><div class="tabs" aria-label="Danışan görünümü">${[['all','Tümü',16],['active','Aktif',16],['archived','Arşiv','']].map(([key,label,count])=>`<button class="tab" data-action="client-tab" data-value="${key}" aria-pressed="${s.tab===key}">${label}${count?` <b>${count}</b>`:''}</button>`).join('')}</div><div class="client-layout"><div class="client-column"><div class="filter-row">${selectControl('Hedef','goal',s.goal,[['','Hedef'],...['Dengeli beslenme','Kilo verme','Kiloyu koruma','Kilo alma'].map(v=>[v,v])],'leaf')}${selectControl('Program durumu','status',s.status,[['','Program durumu'],...['Güncel','Plan güncellenecek','Ölçüm bekleniyor','Program bekliyor'].map(v=>[v,v])])}${selectControl('Son ölçüm','measurement',s.measurement,[['','Son ölçüm'],['recent','Son 7 gün'],['new','Yeni kayıt']],'calendar')}</div><section class="card client-table-card" aria-label="Örnek danışan listesi"><div id="client-table"></div></section></div><aside class="card waiting-card" aria-label="Takip bekleyenler"><h2 class="card-title">Takip bekleyenler</h2><div class="waiting-item"><div class="icon-tile">${icon('layers')}</div><div><h3>Plan güncellemesi</h3><span class="badge-count">3</span><p>Programı güncellenmesi gereken danışanlar.</p><button class="text-button" data-action="waiting-programs">Planları gözden geçir ${icon('arrow')}</button></div></div><div class="waiting-item"><div class="icon-tile">${icon('calendar')}</div><div><h3>Ölçüm hatırlatması</h3><span class="badge-count">2</span><p>Son ölçümü beklenen danışanlar.</p><button class="text-button" data-action="reminder-preview">Hatırlatma gönder ${icon('arrow')}</button></div></div></aside></div>`);
}
function filteredClients() {
  const s=clientState;const q=s.query.toLocaleLowerCase('tr-TR').trim();
  return s.tab==='archived'?[]:samples.filter(c=>(!q||`${c.name} ${c.email}`.toLocaleLowerCase('tr-TR').includes(q))&&(!s.goal||c.goal===s.goal)&&(!s.status||c.state===s.status)&&(!s.measurement||(s.measurement==='new'?c.measurement==='Yeni kayıt':c.measurement!=='Yeni kayıt')));
}
function updateClientTable() {
  const container=document.getElementById('client-table');if(!container)return;
  const rows=filteredClients();const pages=Math.max(1,Math.ceil(rows.length/6));clientState.page=Math.min(clientState.page,pages);
  const pageRows=rows.slice((clientState.page-1)*6,clientState.page*6);
  if(!rows.length){container.innerHTML=`<div class="empty-state">${icon('search')}<h2>${clientState.tab==='archived'?'Arşivde danışan yok':'Aramanıza uygun danışan bulunamadı'}</h2><p>${clientState.tab==='archived'?'Bu önizlemede arşivlenmiş danışan bulunmuyor.':'Arama veya filtrelerini değiştirerek tekrar deneyebilirsin.'}</p><button class="button" data-action="clear-client-filters">Filtreleri temizle</button></div>`;return;}
  container.innerHTML=`<div class="table-scroll"><table><caption class="sr-only">Tamamı sentetik danışanlar ve örnek sağlık değerleri</caption><thead><tr>${['Danışan','Hedef','Son ölçüm','Program','Durum','İşlem'].map(t=>`<th scope="col">${t}</th>`).join('')}</tr></thead><tbody>${pageRows.map(c=>`<tr><td data-label="Danışan"><div class="table-client"><span class="avatar" aria-hidden="true">${initials(c.name)}</span><div><strong>${c.name}</strong><small>${c.email}</small></div></div></td><td data-label="Hedef">${c.goal}</td><td data-label="Son ölçüm">${c.measurement}</td><td data-label="Program">${c.plan}</td><td data-label="Durum"><span class="chip status-chip ${c.state==='Güncel'?'':c.state==='Ölçüm bekleniyor'?'chip-muted':'chip-amber'}">${icon(c.state==='Güncel'?'check':'clock')}${c.state}</span></td><td data-label="İşlem"><button class="button button-small" data-action="client-profile" data-key="${c.key}" aria-label="${c.name} örnek profilini aç">Profili aç ${icon('arrow')}</button></td></tr>`).join('')}</tbody></table></div><nav class="pagination" aria-label="Danışan sayfaları"><span>${(clientState.page-1)*6+1}–${Math.min(clientState.page*6,rows.length)} / ${rows.length} danışan</span><div class="pagination-controls"><button class="page-button edge" data-action="client-page" data-page="${clientState.page-1}" aria-label="Önceki sayfa" ${clientState.page===1?'disabled':''}>${icon('left')}</button>${Array.from({length:pages},(_,i)=>`<button class="page-button" data-action="client-page" data-page="${i+1}" aria-label="${i+1}. sayfayı aç" ${clientState.page===i+1?'aria-current="page"':''}>${i+1}</button>`).join('')}<button class="page-button edge" data-action="client-page" data-page="${clientState.page+1}" aria-label="Sonraki sayfa" ${clientState.page===pages?'disabled':''}>${icon('right')}</button></div><span class="sr-only" role="status">${rows.length} sonuç, sayfa ${clientState.page}</span></nav>`;
}
function programPage() {
  return shell('programlar',header('Programlar','Kendi şablonlarını oluştur, danışanlarına uyarlayarak ata.',`${notificationMenu()}<button class="button button-primary" data-action="new-program">${icon('plus')}Program oluştur</button>`)+`<div class="program-layout ${planState.panel?'':'panel-closed'}"><div class="program-column"><div class="tabs" aria-label="Program görünümü">${[['templates','Şablonlarım'],['assigned','Atanan programlar'],['drafts','Taslaklar']].map(([key,label])=>`<button class="tab" data-action="program-tab" data-value="${key}" aria-pressed="${planState.tab===key}">${label}</button>`).join('')}</div><div class="program-filters"><label class="search-control">${icon('search')}<span class="sr-only">Program ara</span><input id="program-search" type="search" placeholder="Program adı veya etiket ara" value="${escapeHtml(planState.query)}"></label>${selectControl('Program hedefi','goal',planState.goal,[['','Hedef (Tümü)'],...programs.map(p=>[p.tag,p.tag])],'leaf','programs')}${selectControl('Program süresi','duration',planState.duration,[['','Süre (Tümü)'],['7','7 gün'],['14','14 gün']],'calendar','programs')}</div><div id="program-list"></div><section class="recent-plans"><div class="recent-head"><h2>Son atamalar</h2><button class="text-button" data-action="all-assignments">Tüm atamaları gör ${icon('right')}</button></div><div class="card recent-list"><div class="recent-row"><span class="recent-name">${icon('user')}Elif Yılmaz</span><span class="chip">Dengeli Başlangıç</span><span class="recent-date">${icon('calendar')}25 Kasım 2026</span></div><div class="recent-row"><span class="recent-name">${icon('user')}Kerem Kaya</span><span class="chip">Aktif Yaşam</span><span class="recent-date">${icon('calendar')}23 Kasım 2026</span></div></div></section></div><aside class="card assignment-panel" id="assignment-panel" aria-labelledby="assignment-title" ${planState.panel?'':'hidden'}></aside></div>`);
}
function updatePrograms() {
  const container=document.getElementById('program-list');if(!container)return;
  if(planState.tab==='drafts'){
    container.innerHTML=`<div class="card empty-state">${icon('note')}<h2>${draft?'Örnek taslağın hazır':'Henüz taslak yok'}</h2><p>${draft?escapeHtml(draft.title||'Adsız örnek taslak'):'Yeni bir program hazırlayarak görünümü inceleyebilirsin.'}</p><button class="button button-primary" data-action="new-program">${draft?'Taslağı düzenle':'Program oluştur'}</button></div>`;return;
  }
  if(planState.tab==='assigned'){
    container.innerHTML=`<div class="card recent-list"><div class="recent-row"><span class="recent-name">Elif Yılmaz</span><span class="chip">Dengeli Başlangıç</span><button class="button button-small" data-action="assign" data-key="0">Paneli aç ${icon('right')}</button></div><div class="recent-row"><span class="recent-name">Kerem Kaya</span><span class="chip">Aktif Yaşam</span><button class="button button-small" data-action="assign" data-key="1">Paneli aç ${icon('right')}</button></div></div>`;return;
  }
  const q=planState.query.toLocaleLowerCase('tr-TR').trim();
  const items=programs.filter(p=>(!q||`${p.title} ${p.tag}`.toLocaleLowerCase('tr-TR').includes(q))&&(!planState.goal||planState.goal===p.tag)&&(!planState.duration||String(p.days)===planState.duration));
  container.innerHTML=items.length?`<div class="program-cards">${items.map(p=>`<article class="card plan-card ${planState.panel&&planState.selected===p.key?'selected':''}"><div class="plan-card-head">${food(p.photo)}<div><span class="duration">${p.days} gün</span><h2>${p.title}</h2><span class="tag">${p.tag}</span></div></div><div class="calorie-strip">${icon('leaf')}<span>Örnek günlük hedef: <strong>${p.kcal.toLocaleString('tr-TR')} kcal</strong></span></div><p class="plan-meta">${icon('utensils')}6 öğün · Son düzenleme: Bugün</p><div class="plan-actions"><button class="button" data-action="edit-program" data-key="${p.key}">${icon('edit')}Düzenle</button><button class="button button-primary" data-action="assign" data-key="${p.key}" aria-label="${p.title} programını danışana ata">${icon('users')}Danışana ata</button></div></article>`).join('')}</div>`:`<div class="card empty-state">${icon('search')}<h2>Program bulunamadı</h2><p>Arama ve filtrelerini değiştirebilirsin.</p><button class="button" data-action="clear-program-filters">Filtreleri temizle</button></div>`;
}
function weeklyPreview() {
  const labels=['Pzt','Sal','Çar','Per','Cum','Cmt','Paz'];
  const names=['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi','Pazar'];
  const selected=index=>index===planState.day?' class="is-selected"':'';
  return `<div class="week-picker"><table class="week-table" aria-label="Önizleme günü"><thead><tr>${labels.map((label,index)=>`<th scope="col" data-week-day="${index}"${selected(index)} title="${names[index]}">${label}</th>`).join('')}</tr></thead><tbody><tr>${names.map((name,index)=>`<td data-week-day="${index}"${selected(index)}><button class="day-button" data-action="preview-day" data-day="${index}" aria-label="${name}" aria-pressed="${planState.day===index}">${icon('check')}</button></td>`).join('')}</tr></tbody></table></div>`;
}
function assignmentPanel() {
  const p=programs[planState.selected];const panel=document.getElementById('assignment-panel');if(!panel)return;
  panel.hidden=!planState.panel;
  panel.innerHTML=`<div class="panel-heading"><h2 id="assignment-title" tabindex="-1">Danışana program ata</h2><button class="icon-button" data-action="close-panel" aria-label="Atama panelini kapat">${icon('close')}</button></div><p class="panel-subtitle">${p.title}</p><div class="field"><label for="assignment-client-trigger">Danışan</label><div class="input-wrap">${icon('user')}${fields.select({label:'Atanacak danışan',id:'assignment-client',value:planState.client,options:samples.map(c=>[c.key,c.name])})}</div></div><div class="field-grid"><div class="field"><label for="assignment-date-trigger">Başlangıç</label>${fields.date({label:'Başlangıç tarihi',id:'assignment-date',value:planState.start})}</div><div class="field"><label for="assignment-duration-trigger">Süre</label><div class="input-wrap">${fields.select({label:'Atama süresi',id:'assignment-duration',value:planState.durationValue,options:[7,14,21,28].map(d=>[d,`${d} gün`])})}</div></div></div><label class="field">Günlük hedef<span class="input-wrap">${icon('leaf')}<input id="assignment-kcal" type="number" min="1" max="10000" step="1" aria-label="Örnek günlük enerji hedefi (kcal)" value="${planState.kcal}"><span>kcal</span></span></label><section class="week-section"><h3 class="section-heading">Haftalık önizleme</h3>${weeklyPreview()}</section><section class="examples-section"><h3 class="section-heading" id="meal-example-title">${['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi','Pazar'][planState.day]} · Örnek öğünler</h3><div class="meal-examples">${[['Kahvaltı','Yulaf ezmesi, süt, muz, yaban mersini','breakfast-bowl'],['Öğle','Izgara tavuk, bulgur, mevsim salata','balanced-plate'],['Akşam','Yoğurt, ceviz, elma','food-chicken']].map(([title,description,photo])=>`<div class="meal-example">${food(photo,'')}<div><strong>${title}</strong>${description}</div></div>`).join('')}</div></section><label class="check-label"><input id="edit-before-assign" type="checkbox" ${planState.editFirst?'checked':''}>Atamadan önce danışana göre düzenle</label><div class="inline-note">${icon('info')}<span>Danışana özel bir kopya oluşturulur. Ana şablon değişmez.</span></div><div class="panel-footer"><button class="button" data-action="close-panel">Vazgeç</button><button class="button button-primary" data-action="prepare-copy">${planState.editFirst?'Kopyasını oluştur ve düzenle':'Örnek atamayı incele'}</button></div><p class="panel-preview-note">Sentetik önizleme · Gerçek program atanmaz.</p>`;
}
function openAssignment(key) {
  planState.selected=key;planState.panel=true;planState.kcal=String(programs[key].kcal);planState.durationValue=String(programs[key].days);
  document.querySelector('.program-layout').classList.remove('panel-closed');updatePrograms();assignmentPanel();
  document.getElementById('assignment-title').focus({preventScroll:true});
  if(innerWidth<=1000)document.getElementById('assignment-panel').scrollIntoView({behavior:'auto',block:'start'});
}
function editProgram(key,isCopy=false) {
  const p=programs[key];
  if(!draft||draft.key!==key||isCopy)draft={key,title:isCopy?`${p.title} · ${samples[planState.client].name}`:p.title,start:planState.start,kcal:planState.kcal,water:'2000',day:0,meals:['Yulaf ezmesi, süt, muz, yaban mersini','Izgara tavuk, bulgur, mevsim salata','Yoğurt, ceviz, elma']};
  openEditor(isCopy?'Danışana özel örnek program':'Program hazırla');
}
function openEditor(title='Program hazırla') {
  openModal(title,`<p class="subtext">Örnek taslak · Değişiklikler yalnız bu açık önizlemenin belleğinde tutulur.</p><form id="editor-form"><label class="field">Program başlığı<span class="input-wrap"><input id="editor-title" required value="${escapeHtml(draft.title)}"></span></label><div class="field-grid"><div class="field"><label for="editor-start-trigger">Başlangıç tarihi</label>${fields.date({label:"Program başlangıç tarihi",id:"editor-start",value:draft.start,required:true})}</div><label class="field">Günlük enerji (kcal)<span class="input-wrap"><input id="editor-kcal" type="number" min="1" max="10000" required value="${draft.kcal}"></span></label></div><label class="field">Günlük su (mL, isteğe bağlı)<span class="input-wrap"><input id="editor-water" type="number" min="1" max="15000" value="${draft.water}"></span></label><div class="tabs" aria-label="Program günü">${['Her gün','Pzt','Sal','Çar','Per','Cum','Cmt','Paz'].map((d,i)=>`<button class="tab" type="button" data-action="editor-day" data-day="${i}" aria-pressed="${draft.day===i}">${d}</button>`).join('')}</div><p class="subtext" id="editor-day-note">${draft.day===0?'Her güne ait örnek öğün yapısı':'Seçilen güne ait örnek öğün yapısı'}</p>${draft.meals.map((m,i)=>`<label for="editor-meal-${i}">${['Kahvaltı','Öğle','Akşam'][i]}</label><textarea id="editor-meal-${i}" data-meal="${i}" required>${escapeHtml(m)}</textarea>`).join('')}<div class="inline-note">${icon('info')}<span>Bu form görsel ve etkileşim değerlendirmesi içindir. Sağlık kaydı oluşturmaz.</span></div><div class="editor-actions"><button class="button" type="button" data-action="close-modal">Kapat</button><button class="button button-primary" type="submit">Örnek taslağı sakla</button></div></form>`,'editor-dialog');
  document.getElementById('editor-title').focus();
}
function render(focus=false) {
  fields.closeAll();
  const route=location.hash.slice(1)||'giris';currentPage=['giris','danisanlar','programlar'].includes(route)?route:'giris';
  document.querySelectorAll('.preview-bar a').forEach(a=>{if(a.hash===`#${currentPage}`)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current');});
  app.innerHTML=currentPage==='giris'?loginPage():currentPage==='danisanlar'?clientsPage():programPage();
  if(currentPage==='danisanlar')updateClientTable();
  if(currentPage==='programlar'){updatePrograms();assignmentPanel();}
  document.title=`${{giris:'Giriş',danisanlar:'Danışanlar',programlar:'Programlar'}[currentPage]} · Limely önizleme`;
  if(focus){window.scrollTo(0,0);document.querySelector('main h1')?.focus({preventScroll:true});}
}

document.addEventListener('click',event=>{
  const el=event.target.closest('[data-action]');if(!el)return;const action=el.dataset.action;
  if(action==='close-modal'){closeModal();return;}
  if(action==='toggle-menu'){
    const opened=document.querySelector('.sidebar').classList.toggle('menu-open');el.setAttribute('aria-expanded',String(opened));el.setAttribute('aria-label',opened?'Menüyü kapat':'Menüyü aç');el.innerHTML=icon(opened?'close':'menu');return;
  }
  if(action==='scope'){info(el.dataset.label,`${el.dataset.label} için mevcut uygulama route’u korunur. İlk tasarım tesliminde giriş, danışan listesi ve program hazırlama/atama ekranları hazırlanmıştır.`);return;}
  if(action==='legal'){info(el.dataset.label,'Bu önizleme canlı bir hesap veya sağlık kaydı oluşturmaz. Üretim gizlilik ve kullanım metinleri burada temsil edilmemiştir.');return;}
  if(action==='toggle-password'){const input=document.getElementById('login-password');const shown=input.type==='password';input.type=shown?'text':'password';el.textContent=shown?'Gizle':'Göster';el.setAttribute('aria-pressed',String(shown));return;}
  if(action==='reset-preview'){openModal('Şifremi unuttum',`<p>Yerleşimi incelemek için örnek e-posta adresi kullanabilirsin.</p><form id="reset-form"><label for="reset-email">E-posta</label><div class="input-wrap"><input id="reset-email" type="email" placeholder="ornek@example.test" required autocomplete="off"></div><button class="button button-primary" type="submit">Önizlemeyi dene</button></form><p class="auth-synthetic">E-posta gönderilmez.</p>`);return;}
  if(action==='apply-preview'){info('Diyetisyen hesabı oluştur','Webde diyetisyen başvurusu kullanılır. Danışan kaydı mobil uygulamada yapılır. Hesap oluşturma bu önizlemenin kapsamında değildir.');return;}
  if(action==='invite'){openModal('Danışan ekle',`<p>Danışanınla bağlantı kurmak için davet alanı.</p><div class="inline-note">${icon('users')}<span><strong>Örnek davet kodu: LM-DEMO</strong><br>Bu kod canlı sistemde geçerli değildir.</span></div><p class="subtext">Önizlemede davet gönderilmez ve yeni danışan oluşturulmaz.</p><button class="button button-primary" data-action="close-modal">Tamam</button>`);return;}
  if(action==='go-programs'){location.hash='programlar';return;}
  if(action==='client-tab'){clientState.tab=el.dataset.value;clientState.page=1;document.querySelectorAll('[data-action="client-tab"]').forEach(b=>b.setAttribute('aria-pressed',String(b===el)));updateClientTable();return;}
  if(action==='client-page'){clientState.page=Number(el.dataset.page);updateClientTable();document.querySelector(`[data-action="client-page"][data-page="${clientState.page}"][aria-current]`)?.focus();return;}
  if(action==='clear-client-filters'){clientState={tab:'all',query:'',goal:'',status:'',measurement:'',page:1};render();document.getElementById('client-search').focus();return;}
  if(action==='client-profile'){
    const c=samples[Number(el.dataset.key)];openModal(`${c.name} · Örnek profil`,`<p><span class="chip">Sentetik danışan</span></p><p><strong>Hedef:</strong> ${c.goal}<br><strong>Program:</strong> ${c.plan}<br><strong>Son ölçüm:</strong> ${c.measurement}</p><div class="inline-note">${icon('shield')}<span>Canlı uygulamada her kayıt kategorisi danışanın paylaşım iznine bağlıdır.</span></div><button class="button button-primary" data-action="profile-program" data-key="${c.key}">Program panelini aç ${icon('arrow')}</button>`);return;
  }
  if(action==='profile-program'){planState.client=Number(el.dataset.key);closeModal();location.hash='programlar';return;}
  if(action==='waiting-programs'){clientState.status='Plan güncellenecek';clientState.page=1;render();document.getElementById('clients-status-trigger').focus();return;}
  if(action==='reminder-preview'){info('Ölçüm hatırlatması','Hatırlatma alanı tasarım örneğidir. Mevcut API bildirim teslimi sağlamadığı için herhangi bir mesaj gönderilmez.');return;}
  if(action==='program-tab'){planState.tab=el.dataset.value;document.querySelectorAll('[data-action="program-tab"]').forEach(b=>b.setAttribute('aria-pressed',String(b===el)));updatePrograms();return;}
  if(action==='all-assignments'){planState.tab='assigned';document.querySelectorAll('[data-action="program-tab"]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.value==='assigned')));updatePrograms();document.querySelector('[data-action="program-tab"][data-value="assigned"]').focus();return;}
  if(action==='clear-program-filters'){planState.query='';planState.goal='';planState.duration='';render();document.getElementById('program-search').focus();return;}
  if(action==='assign'){openAssignment(Number(el.dataset.key));return;}
  if(action==='close-panel'){planState.panel=false;document.getElementById('assignment-panel').hidden=true;document.querySelector('.program-layout').classList.add('panel-closed');updatePrograms();document.querySelector(`[data-action="assign"][data-key="${planState.selected}"]`)?.focus();return;}
  if(action==='preview-day'){planState.day=Number(el.dataset.day);document.querySelectorAll('[data-action="preview-day"]').forEach(b=>b.setAttribute('aria-pressed',String(b===el)));document.querySelectorAll('[data-week-day]').forEach(cell=>cell.classList.toggle('is-selected',Number(cell.dataset.weekDay)===planState.day));document.getElementById('meal-example-title').textContent=`${['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi','Pazar'][planState.day]} · Örnek öğünler`;return;}
  if(action==='new-program'){if(!draft)draft={key:-1,title:'',start:'2026-11-25',kcal:'',water:'',day:0,meals:['','','']};openEditor('Yeni program hazırla');return;}
  if(action==='edit-program'){planState.kcal=String(programs[Number(el.dataset.key)].kcal);editProgram(Number(el.dataset.key));return;}
  if(action==='prepare-copy'){
    const date=document.getElementById('assignment-date'),kcal=document.getElementById('assignment-kcal');
    if(!date.value||!date.checkValidity()){date.reportValidity();date.focus();return;}
    if(!kcal.value||!kcal.checkValidity()){kcal.reportValidity();kcal.focus();return;}
    if(planState.editFirst)editProgram(planState.selected,true);else info('Örnek atama özeti',`${samples[planState.client].name} için ${programs[planState.selected].title}, ${planState.durationValue} gün. Yalnız önizleme; gerçek program atanmamıştır.`);return;
  }
  if(action==='editor-day'){draft.day=Number(el.dataset.day);document.querySelectorAll('[data-action="editor-day"]').forEach(b=>b.setAttribute('aria-pressed',String(b===el)));document.getElementById('editor-day-note').textContent=draft.day===0?'Her güne ait örnek öğün yapısı':'Seçilen güne ait örnek öğün yapısı';return;}
});
document.addEventListener('input',event=>{
  const el=event.target;
  if(el.id==='client-search'){clientState.query=el.value;clientState.page=1;updateClientTable();}
  if(el.id==='program-search'){planState.query=el.value;updatePrograms();}
  if(el.id==='assignment-date')planState.start=el.value;
  if(el.id==='assignment-kcal')planState.kcal=el.value;
  if(draft&&el.id==='editor-title')draft.title=el.value;
  if(draft&&el.id==='editor-start')draft.start=el.value;
  if(draft&&el.id==='editor-kcal')draft.kcal=el.value;
  if(draft&&el.id==='editor-water')draft.water=el.value;
  if(draft&&el.dataset.meal!==undefined)draft.meals[Number(el.dataset.meal)]=el.value;
});
document.addEventListener('change',event=>{
  const el=event.target;
  if(el.dataset.filter){if(el.dataset.scope==='clients'){clientState[el.dataset.filter]=el.value;clientState.page=1;updateClientTable();}else{planState[el.dataset.filter]=el.value;updatePrograms();}}
  if(el.id==='assignment-client')planState.client=Number(el.value);
  if(el.id==='assignment-duration')planState.durationValue=el.value;
  if(el.id==='edit-before-assign'){planState.editFirst=el.checked;document.querySelector('[data-action="prepare-copy"]').textContent=el.checked?'Kopyasını oluştur ve düzenle':'Örnek atamayı incele';}
});
document.addEventListener('submit',event=>{
  event.preventDefault();
  if(event.target.id==='login-form'){
    const email=document.getElementById('login-email'),password=document.getElementById('login-password'),error=document.getElementById('login-error');
    const invalid=!email.value||!email.validity.valid?email:password.value.length<8?password:null;
    if(invalid){error.hidden=false;error.textContent=invalid===email?'Geçerli bir örnek e-posta adresi gir.':'Örnek şifre en az 8 karakter olmalı.';invalid.setAttribute('aria-invalid','true');invalid.focus();return;}
    email.removeAttribute('aria-invalid');password.removeAttribute('aria-invalid');location.hash='danisanlar';notify('Örnek çalışma alanı açıldı. Gerçek oturum oluşturulmadı.');
  }
  if(event.target.id==='reset-form'){closeModal();notify('Önizleme tamamlandı. E-posta gönderilmedi.');}
  if(event.target.id==='editor-form'){closeModal();if(currentPage==='programlar'&&planState.tab==='drafts')updatePrograms();notify('Örnek taslak bu sekmenin belleğinde saklandı. Gerçek kayıt oluşturulmadı.');}
});
document.addEventListener('keydown',event=>{
  if(event.key!=='Escape'||modal.open)return;
  const openDetails=[...document.querySelectorAll('details[open]')];
  if(openDetails.length){openDetails.forEach(d=>d.open=false);openDetails[0].querySelector('summary').focus();return;}
  const sidebarNode=document.querySelector('.sidebar.menu-open');
  if(sidebarNode){sidebarNode.classList.remove('menu-open');const b=sidebarNode.querySelector('.mobile-menu');b.setAttribute('aria-expanded','false');b.setAttribute('aria-label','Menüyü aç');b.innerHTML=icon('menu');b.focus();}
});
document.addEventListener('click',event=>{document.querySelectorAll('details[open]').forEach(d=>{if(!d.contains(event.target))d.open=false;});});
window.addEventListener('hashchange',()=>{if(modal.open)modal.close();render(true);});
render();
