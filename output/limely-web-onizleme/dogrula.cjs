const { chromium, expect } = require('../../apps/web/node_modules/@playwright/test');
const { mkdir, writeFile, readFile } = require('node:fs/promises');
const { createHash } = require('node:crypto');
const { resolve, join } = require('node:path');
const { pathToFileURL } = require('node:url');

async function main() {
  const folder=__dirname, shots=join(folder,'gorseller'); await mkdir(shots,{recursive:true});
  const browser=await chromium.launch({channel:'msedge',headless:true});
  const context=await browser.newContext({locale:'tr-TR',timezoneId:'Europe/Istanbul',colorScheme:'light',reducedMotion:'reduce'});
  const page=await context.newPage();
  const errors=[], network=[]; const checks=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('request',r=>{if(/^https?:/.test(r.url()))network.push({url:r.url(),method:r.method()});});
  const base=pathToFileURL(join(folder,'index.html')).href;
  async function go(route){await page.goto(`${base}#${route}`);await page.locator('h1').waitFor();await page.evaluate(()=>document.fonts.ready);await page.waitForFunction(()=>[...document.images].every(i=>i.complete));}
  async function selectOption(label,value){
    await page.getByRole('combobox',{name:label,exact:true}).click();
    await page.getByRole('listbox',{name:`${label} seçenekleri`,exact:true}).locator(`[data-value="${value}"]`).click();
  }
  async function check(label,run){await run();checks.push(label);console.log('PASS '+label);}
  try {
    await check('Sol menü: kendi sütununda taşma ve yakınlaştırma benzetimi',async()=>{
      for(const width of [1585,1440,1366,1280,1100,1024]){
        await page.setViewportSize({width,height:1024});await go('danisanlar');
        for(const zoom of [1,1.25,1.5]){
          await page.evaluate(value=>{document.documentElement.style.zoom=String(value);},zoom);
          const overflow=await page.locator('.sidebar').evaluate(sidebar=>{
            const bounds=sidebar.getBoundingClientRect();
            return [...sidebar.querySelectorAll('.sidebar-content,.side-nav,.side-link,.side-link>span,.profile-menu,.profile-menu summary,.profile-menu summary>span')].flatMap(el=>{
              const rect=el.getBoundingClientRect();
              if(!rect.width||!rect.height)return [];
              const outside=rect.left<bounds.left-.5||rect.right>bounds.right+.5;
              const clipped=el.scrollWidth>el.clientWidth+1;
              return outside||clipped?[{label:el.textContent.trim(),outside,clipped,right:rect.right,sidebarRight:bounds.right}]:[];
            });
          });
          if(overflow.length)await page.locator('.sidebar').screenshot({path:join(shots,'sol-menu-tasma.png')});
          expect(overflow,`${width}px, yakınlaştırma ${zoom}`).toEqual([]);
          if(width===1440&&zoom===1.25)await page.locator('.sidebar').screenshot({path:join(shots,'sol-menu-125.png')});
        }
        await page.evaluate(()=>{document.documentElement.style.zoom='';});
      }
    });
    for(const [width,height] of [[1585,1024],[1024,1024],[768,1024],[390,844]]){
      await page.setViewportSize({width,height});
      for(const route of ['giris','danisanlar','programlar']){
        await go(route);
        await check(`${route}: ${width}px taşma, varlık, font ve zemin`,async()=>{
          expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
          expect(await page.evaluate(()=>[...document.images].filter(i=>!i.naturalWidth).map(i=>i.src))).toEqual([]);
          expect(await page.locator('h1').evaluate(el=>getComputedStyle(el).fontFamily)).toContain('Manrope');
          expect(await page.locator('body').evaluate(el=>getComputedStyle(el).fontFamily)).toContain('Inter');
          expect(await page.locator('.preview-stage').evaluate(el=>getComputedStyle(el).backgroundColor)).toBe('rgb(248, 250, 242)');
          expect(await page.evaluate(()=>document.fonts.check('700 18px Manrope')&&document.fonts.check('400 16px Inter'))).toBe(true);
          expect(await page.locator('button:visible, a:visible, input:visible, select:visible').evaluateAll(nodes=>nodes.filter(el=>el.getBoundingClientRect().right>innerWidth+1||el.getBoundingClientRect().left< -1).map(el=>el.outerHTML.slice(0,180)))).toEqual([]);
        });
        await page.locator('.preview-stage').screenshot({path:join(shots,`${route}-${width}.png`)});
        if(width===1585&&route==='giris'){await page.setViewportSize({width:1536,height:1024});await page.locator('.auth-shell').screenshot({path:join(shots,'giris-panel-706.png')});await page.locator('.preview-stage').screenshot({path:join(shots,'giris-1536.png')});await page.setViewportSize({width,height});}
      }
    }
    await check('Haftalık önizleme: yedi eşit sütun, başlık/işaret hizası ve klavye seçimi',async()=>{
      const days=['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi','Pazar'];
      for(const width of [1585,1280,1024,768,390]){
        await page.setViewportSize({width,height:1024});await go('programlar');
        const table=page.getByRole('table',{name:'Önizleme günü'});
        await expect(table.getByRole('columnheader')).toHaveCount(7);
        await expect(table.getByRole('button')).toHaveCount(7);
        const dimensions=await table.evaluate(node=>{
          const columns=[...node.querySelectorAll('th')].map(el=>el.getBoundingClientRect());
          const cells=[...node.querySelectorAll('td')].map(el=>el.getBoundingClientRect());
          const icons=[...node.querySelectorAll('button .icon')].map(el=>el.getBoundingClientRect());
          return columns.map((column,index)=>({width:column.width,cellWidth:cells[index].width,leftDelta:Math.abs(column.left-cells[index].left),rowGap:Math.abs(column.bottom-cells[index].top),centerDelta:Math.abs((column.left+column.right-icons[index].left-icons[index].right)/2)}));
        });
        expect(Math.max(...dimensions.map(d=>d.width))-Math.min(...dimensions.map(d=>d.width))).toBeLessThan(1);
        for(const dimension of dimensions){
          expect(Math.abs(dimension.width-dimension.cellWidth)).toBeLessThan(1);
          expect(dimension.leftDelta).toBeLessThan(1);
          expect(dimension.rowGap).toBeLessThan(1);
          expect(dimension.centerDelta).toBeLessThan(1);
        }
        for(const [index,day] of days.entries()){
          await table.getByRole('button',{name:day,exact:true}).click();
          await expect(table.locator('button[aria-pressed="true"]')).toHaveCount(1);
          await expect(page.locator('#meal-example-title')).toContainText(day);
          expect(await table.getByRole('columnheader').nth(index).evaluate(el=>getComputedStyle(el).backgroundColor)).toBe('rgb(201, 232, 121)');
        }
        await table.getByRole('button',{name:'Pazartesi',exact:true}).focus();
        await page.keyboard.press('Tab');
        await expect(table.getByRole('button',{name:'Salı',exact:true})).toBeFocused();
        await page.keyboard.press('Space');
        await expect(table.getByRole('button',{name:'Salı',exact:true})).toHaveAttribute('aria-pressed','true');
        await table.getByRole('button',{name:'Pazartesi',exact:true}).click();
        await page.locator('#assignment-title').focus();
        if(width===1585||width===390)await page.locator('.week-section').screenshot({path:join(shots,`haftalik-onizleme-${width}.png`)});
      }
    });
    await page.setViewportSize({width:1585,height:1024});
    await go('giris');
    await check('Giriş: doğrulama, şifre görünürlüğü, örnek geçiş',async()=>{
      await page.getByRole('button',{name:'Giriş yap',exact:true}).click();
      await expect(page.locator('#login-email')).toBeFocused();
      await expect(page.getByRole('alert')).toContainText('örnek e-posta');
      await page.locator('#login-email').fill('ornek@example.test');
      await page.locator('#login-password').fill('Ornek1234');
      await page.getByRole('button',{name:'Göster',exact:true}).click();
      await expect(page.locator('#login-password')).toHaveAttribute('type','text');
      await page.getByRole('button',{name:'Gizle',exact:true}).click();
      await expect(page.locator('#login-password')).toHaveAttribute('type','password');
      await page.getByRole('button',{name:'Giriş yap',exact:true}).click();
      await expect(page.locator('h1')).toHaveText('Danışanlar');
    });
    await check('Danışanlar: arama, boş sonuç, filtreler, sayfalama, arşiv',async()=>{
      await page.getByRole('searchbox',{name:'Danışan ara'}).fill('Olmayan sentetik kişi');
      await expect(page.getByText('Aramanıza uygun danışan bulunamadı')).toBeVisible();
      await page.getByRole('button',{name:'Filtreleri temizle'}).click();
      await page.getByRole('searchbox',{name:'Danışan ara'}).fill('Elif');
      await expect(page.locator('tbody tr')).toHaveCount(1);
      await page.getByRole('searchbox',{name:'Danışan ara'}).fill('');
      await selectOption('Hedef','Kilo verme');
      await expect(page.locator('tbody tr')).toHaveCount(6);
      await selectOption('Hedef','');
      await selectOption('Program durumu','Ölçüm bekleniyor');
      await expect(page.locator('tbody tr')).toHaveCount(3);
      await selectOption('Program durumu','');
      await page.getByRole('button',{name:'2. sayfayı aç'}).click();
      await expect(page.getByRole('navigation',{name:'Danışan sayfaları'})).toContainText('7–12 / 16');
      await page.getByRole('button',{name:'Arşiv',exact:true}).click();
      await expect(page.getByText('Arşivde danışan yok')).toBeVisible();
      await page.getByRole('button',{name:'Tümü 16',exact:true}).click();
      await expect(page.locator('tbody tr')).toHaveCount(6);
    });
    await check('Açılır menüler: klavye ve odak dönüşü',async()=>{
      await page.getByLabel('Örnek bildirimleri aç').focus();
      await page.keyboard.press('Enter');
      await expect(page.getByText('Örnek bildirimler',{exact:true})).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.getByLabel('Örnek bildirimleri aç')).toBeFocused();
      await page.locator('.profile-menu summary').focus();
      await page.keyboard.press('Enter');
      await expect(page.getByText('Sentetik diyetisyen profili')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.locator('.profile-menu summary')).toBeFocused();
    });
    await check('Örnek profil penceresi: açılış, odak sınırı ve kapanış',async()=>{
      const trigger=page.getByRole('button',{name:'Elif Yılmaz örnek profilini aç'});
      await trigger.click();
      await expect(page.getByRole('dialog')).toBeVisible();
      for(let i=0;i<9;i++)await page.keyboard.press('Tab');
      expect(await page.evaluate(()=>document.querySelector('dialog').contains(document.activeElement))).toBe(true);
      await page.keyboard.press('Escape');await expect(trigger).toBeFocused();
    });
    await go('programlar');
    await check('Programlar: arama, süre/hedef filtreleri ve sekmeler',async()=>{
      await page.getByRole('searchbox',{name:'Program ara'}).fill('Olmayan');
      await expect(page.getByText('Program bulunamadı',{exact:true})).toBeVisible();
      await page.getByRole('button',{name:'Filtreleri temizle'}).click();
      await selectOption('Program süresi','14');
      await expect(page.locator('.plan-card')).toHaveCount(1);
      await selectOption('Program süresi','');
      await selectOption('Program hedefi','Dengeli beslenme');
      await expect(page.locator('.plan-card')).toHaveCount(1);
      await selectOption('Program hedefi','');
      await page.getByRole('button',{name:'Atanan programlar',exact:true}).click();
      await expect(page.getByRole('button',{name:'Paneli aç'})).toHaveCount(2);
      await page.getByRole('button',{name:'Taslaklar',exact:true}).click();
      await expect(page.getByText('Henüz taslak yok')).toBeVisible();
      await page.getByRole('button',{name:'Şablonlarım',exact:true}).click();
      await expect(page.locator('.plan-card')).toHaveCount(4);
    });
    await check('Program paneli: kapatma/açma, danışan, gün, kopya ve taslak koruma',async()=>{
      await page.getByRole('button',{name:'Atama panelini kapat'}).click();
      await expect(page.locator('#assignment-panel')).toBeHidden();
      await page.getByRole('button',{name:'Aktif Yaşam programını danışana ata'}).click();
      await expect(page.locator('#assignment-panel')).toBeVisible();
      await expect(page.locator('#assignment-title')).toBeFocused();
      await selectOption('Atanacak danışan','1');
      await page.getByRole('button',{name:'Cuma',exact:true}).click();
      await expect(page.getByRole('button',{name:'Cuma',exact:true})).toHaveAttribute('aria-pressed','true');
      await expect(page.locator('#meal-example-title')).toContainText('Cuma');
      await page.getByRole('button',{name:'Kopyasını oluştur ve düzenle'}).click();
      await expect(page.getByRole('dialog')).toBeVisible();
      await expect(page.locator('#editor-title')).toHaveValue('Aktif Yaşam · Kerem Kaya');
      await page.locator('#editor-title').fill('Sentetik özel program');
      await page.getByRole('button',{name:'Örnek taslağı sakla'}).click();
      await expect(page.getByRole('dialog')).not.toBeVisible();
      await page.getByRole('button',{name:'Taslaklar',exact:true}).click();
      await expect(page.getByText('Sentetik özel program',{exact:true})).toBeVisible();
      await page.getByRole('button',{name:'Taslağı düzenle'}).click();
      await expect(page.locator('#editor-title')).toHaveValue('Sentetik özel program');
      await page.keyboard.press('Escape');
    });
    await check('Telefon: menü klavye erişimi, görünür odak, panel ve form taşması',async()=>{
      await page.setViewportSize({width:390,height:844});await go('danisanlar');
      await page.getByRole('button',{name:'Menüyü aç'}).click();
      await expect(page.getByRole('navigation',{name:'Diyetisyen çalışma alanı'})).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.getByRole('button',{name:'Menüyü aç'})).toBeFocused();
      expect(await page.getByRole('button',{name:'Menüyü aç'}).evaluate(el=>getComputedStyle(el).outlineStyle)).toBe('solid');
      await page.getByRole('button',{name:'Menüyü aç'}).click();
      await page.getByRole('link',{name:'Programlar',exact:true}).last().click();
      await page.getByRole('button',{name:'Şablonlarım',exact:true}).click();
      await page.getByRole('button',{name:'Dengeli Başlangıç programını danışana ata'}).click();
      await expect(page.locator('#assignment-title')).toBeInViewport();
      await page.getByRole('button',{name:'Kopyasını oluştur ve düzenle'}).click();
      expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
      expect(await page.locator('dialog').evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true);
      await page.screenshot({path:join(shots,'program-duzenleme-390.png'),fullPage:true});
      await page.keyboard.press('Escape');
    });
    await check('Yedi özel seçim: açık liste, seçili satır ve dört genişlikte ekran sınırları',async()=>{
      await expect(page.locator('#toast')).toBeHidden({timeout:7000});
      for(const width of [1585,1024,768,390]){
        await page.setViewportSize({width,height:844});
        for(const route of ['danisanlar','programlar']){
          await go(route);
          await expect(page.locator('select:visible')).toHaveCount(0);
          const selectors=page.getByRole('combobox');
          await expect(selectors).toHaveCount(route==='danisanlar'?3:4);
          for(let index=0;index<await selectors.count();index++){
            const trigger=selectors.nth(index);await trigger.click();
            await expect(trigger).toHaveAttribute('aria-expanded','true');
            const menu=page.getByRole('listbox');await expect(menu).toBeVisible();
            await expect(menu.locator('[aria-selected="true"]')).toHaveCount(1);
            const bounds=await menu.boundingBox();
            expect(bounds.x).toBeGreaterThanOrEqual(11);
            expect(bounds.x+bounds.width).toBeLessThanOrEqual(width-11);
            expect(bounds.y).toBeGreaterThanOrEqual(11);
            expect(bounds.y+bounds.height).toBeLessThanOrEqual(833);
            expect(await menu.evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true);
            if(route==='programlar'&&index===0&&(width===1585||width===390))await page.screenshot({path:join(shots,`acilir-secim-${width}.png`)});
            if(route==='programlar'&&index===2&&width===390)await page.screenshot({path:join(shots,'danisan-secimi-390.png')});
            await page.keyboard.press('Escape');
            await expect(trigger).toHaveAttribute('aria-expanded','false');
            await expect(trigger).toBeFocused();
          }
        }
      }
    });
    await check('Özel seçim klavyesi: oklar, Home/End, arama, Enter, Tab ve dışarı tıklama',async()=>{
      await page.setViewportSize({width:1585,height:1024});await go('programlar');
      const goal=page.getByRole('combobox',{name:'Program hedefi',exact:true});
      await goal.focus();await page.keyboard.press('End');await page.keyboard.press('Enter');
      await expect(page.locator('#programs-goal')).toHaveValue('Kiloyu koruma');
      await expect(page.locator('.plan-card')).toHaveCount(1);
      await goal.click();await page.keyboard.press('Home');await page.keyboard.press('Enter');
      await expect(page.locator('.plan-card')).toHaveCount(4);
      await goal.click();await page.keyboard.press('ArrowDown');await page.keyboard.press('Escape');
      await expect(page.locator('#programs-goal')).toHaveValue('');
      await goal.click();await page.keyboard.press('Tab');
      await expect(goal).toHaveAttribute('aria-expanded','false');
      expect(await goal.evaluate(el=>el===document.activeElement)).toBe(false);
      const client=page.getByRole('combobox',{name:'Atanacak danışan',exact:true});
      await client.click();await page.keyboard.press('k');await page.keyboard.press('e');await page.keyboard.press('r');await page.keyboard.press('Enter');
      await expect(page.locator('#assignment-client')).toHaveValue('1');
      await client.click();await page.keyboard.press('End');
      await expect(page.getByRole('option',{name:'Aylin Koç',exact:true})).toBeInViewport();
      await page.keyboard.press('Escape');await expect(page.locator('#assignment-client')).toHaveValue('1');
      await goal.click();await page.mouse.click(2,2);await expect(goal).toHaveAttribute('aria-expanded','false');
    });
    await check('Takvimler: tarih aktarımı, ay geçişi, klavye ve diyalog üstünde açılma',async()=>{
      await go('programlar');
      const dateTrigger=page.getByRole('button',{name:'Başlangıç tarihi',exact:true});
      await dateTrigger.click();
      const calendar=page.getByRole('dialog',{name:'Başlangıç tarihi seç',exact:true});
      await expect(calendar).toBeVisible();
      await expect(calendar.getByRole('columnheader')).toHaveCount(7);
      await calendar.getByRole('gridcell',{name:'27 Kasım 2026',exact:true}).click();
      await expect(page.locator('#assignment-date')).toHaveValue('2026-11-27');
      await expect(dateTrigger).toBeFocused();
      await dateTrigger.click();await page.keyboard.press('PageDown');
      await expect(calendar.getByRole('heading')).toHaveText('Aralık 2026');
      await page.keyboard.press('PageUp');await page.keyboard.press('Home');await page.keyboard.press('Enter');
      await expect(page.locator('#assignment-date')).toHaveValue('2026-11-23');
      await dateTrigger.click();await calendar.getByRole('button',{name:'Sonraki ay',exact:true}).click();
      await expect(calendar.getByRole('heading')).toHaveText('Aralık 2026');
      await calendar.getByRole('button',{name:'Önceki ay',exact:true}).click();
      await page.screenshot({path:join(shots,'tarih-secimi-1585.png')});
      await page.keyboard.press('Escape');
      await page.getByRole('button',{name:'Program oluştur',exact:true}).click();
      await page.getByRole('button',{name:'Program başlangıç tarihi',exact:true}).click();
      const editorCalendar=page.getByRole('dialog',{name:'Program başlangıç tarihi seç',exact:true});
      await expect(editorCalendar).toBeVisible();
      await editorCalendar.getByRole('gridcell',{name:'28 Kasım 2026',exact:true}).click();
      await expect(page.locator('#editor-start')).toHaveValue('2026-11-28');
      await page.getByRole('button',{name:'Program başlangıç tarihi',exact:true}).click();
      await page.keyboard.press('Escape');
      await expect(page.locator('#modal')).toBeVisible();
      await page.keyboard.press('Escape');
      for(const width of [768,390]){
        await page.setViewportSize({width,height:844});await go('programlar');
        await page.getByRole('button',{name:'Başlangıç tarihi',exact:true}).click();
        const mobileCalendar=page.getByRole('dialog',{name:'Başlangıç tarihi seç',exact:true});
        const bounds=await mobileCalendar.boundingBox();
        expect(bounds.x).toBeGreaterThanOrEqual(11);
        expect(bounds.x+bounds.width).toBeLessThanOrEqual(width-11);
        expect(bounds.y).toBeGreaterThanOrEqual(11);
        expect(bounds.y+bounds.height).toBeLessThanOrEqual(833);
        expect(await mobileCalendar.evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true);
        if(width===390)await page.screenshot({path:join(shots,'tarih-secimi-390.png')});
        await page.keyboard.press('Escape');
      }
    });
    await check('Kaynak marka varlıklarının SHA-256 bütünlüğü',async()=>{
      const copied=JSON.parse(await readFile(join(folder,'varlik-kaynaklari.json'),'utf8'));
      for(const item of copied){const original=await readFile(resolve(folder,'../..',item.source));const copy=await readFile(join(folder,item.target));expect(original.equals(copy)).toBe(true);expect(createHash('sha256').update(copy).digest('hex')).toBe(item.sha256);}
    });
    await check('Karşılaştırma sayfası: kaynak görseller, masaüstü ve telefon taşması',async()=>{
      await page.goto(pathToFileURL(join(folder,'karsilastirma.html')).href);
      await page.locator('h1').waitFor();
      await page.locator('img').evaluateAll(nodes=>nodes.forEach(node=>node.loading='eager'));
      await page.waitForFunction(()=>[...document.images].every(i=>i.complete));
      expect(await page.evaluate(()=>[...document.images].filter(i=>!i.naturalWidth).map(i=>i.src))).toEqual([]);
      for(const width of [1585,390]){
        await page.setViewportSize({width,height:1024});
        expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
      }
      await page.setViewportSize({width:1585,height:1024});
      await page.screenshot({path:join(shots,'inceleme-sayfasi-1585.png')});
    });
    expect(errors).toEqual([]);expect(network).toEqual([]);
    checks.push('JavaScript/konsol hatası yok; HTTP/API isteği yok');
    const report={date:'2026-11-25',engine:'Microsoft Edge / Playwright 1.65.1',mode:'file:// — sentetik HTML önizlemesi',checks,errors,network,passed:true};
    await writeFile(join(folder,'dogrulama-sonuclari.json'),JSON.stringify(report,null,2)+'\n');
    console.log(`PASS ${checks.length} kontrol; HTTP/API istekleri: 0; konsol hataları: 0`);
  } finally {await browser.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
