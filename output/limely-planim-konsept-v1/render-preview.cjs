// Render the design HTML itself. No application, API or account is accessed.
// node render-preview.cjs <directory containing the bundled node_modules>
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');
const packages = process.argv[2];
if (!packages) throw new Error('Pass the directory containing the bundled node_modules.');
const { chromium } = require(require.resolve('playwright', { paths: [packages] }));
const local = name => pathToFileURL(path.join(__dirname, name)).href;
const brand = name => pathToFileURL(path.join(__dirname, '../limely-marka-paketi-v1', name)).href;

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 920 }, deviceScaleFactor: 2, timezoneId: 'Europe/Istanbul', reducedMotion: 'reduce' });
    const page = await context.newPage();
    const errors = [], network = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', request => errors.push(request.url() + ': ' + request.failure().errorText));
    page.on('request', request => { if (/^https?:/.test(request.url())) network.push(request.url()); });
    async function open() {
      await page.goto(local('limely-planim.html'));
      await page.evaluate(() => document.fonts.ready);
      await page.locator('img').evaluateAll(images => Promise.all(images.map(i => i.decode())));
      assert.deepEqual(await page.locator('img').evaluateAll(images => images.filter(i => !i.complete || !i.naturalWidth).map(i => i.src)), []);
    }
    await open();
    assert.equal(await page.evaluate(() => document.fonts.check('16px Figtree')), true);
    assert.deepEqual(await page.locator('.bottom-nav button').allTextContents(), ['Günüm', 'Ölçüm', 'Planım', 'Sohbet', 'Hesabım']);
    assert.equal(await page.locator('.bottom-nav [aria-current="page"]').textContent(), 'Planım');
    assert.equal(await page.locator('.meal-card').count(), 4);
    assert.equal(await page.locator('.day-button[aria-pressed="true"]').getAttribute('data-date'), '2026-11-27');
    const initialTargets = await page.locator('.targets').textContent();
    await page.screenshot({ path: path.join(__dirname, 'limely-planim-ilk-ekran.png'), animations: 'disabled' });
    await page.locator('#meal-lunch .alternative summary').click();
    assert.equal(await page.locator('#meal-lunch .alternative').getAttribute('open'), '');
    assert.equal(await page.getByText('Tam tahıllı ekmek', { exact: true }).first().isVisible(), true);
    assert.equal(await page.locator('#meal-lunch .or').textContent(), 'veya');
    await page.locator('.page-scroll').evaluate(el => { el.scrollTop += document.querySelector('#meal-lunch').getBoundingClientRect().top - el.getBoundingClientRect().top - 20; });
    await page.screenshot({ path: path.join(__dirname, 'limely-planim-devam.png'), animations: 'disabled' });
    await page.locator('#open-review').click();
    assert.equal(await page.locator('#comparison-panel').getByText('980', { exact: false }).isVisible(), true);
    await page.screenshot({ path: path.join(__dirname, 'limely-planim-karsilastirma.png'), animations: 'disabled' });
    await page.getByRole('tab', { name: 'Karşılaştırma', exact: true }).focus();
    await page.keyboard.press('ArrowRight');
    assert.equal(await page.getByRole('tab', { name: 'Kaydettiğin öğünler', exact: true }).getAttribute('aria-selected'), 'true');
    assert.equal(await page.locator('#logs-panel').getByText('Yumurtalı tam tahıllı tost', { exact: false }).isVisible(), true);
    await page.keyboard.press('Escape');
    await page.locator('#page-scroll').evaluate(el => el.scrollTop = 0);
    await page.getByRole('button', { name: 'Plan bilgisini aç', exact: true }).click();
    assert.equal(await page.locator('#info-dialog').getByText('Uğur Çetin', { exact: true }).isVisible(), true);
    await page.screenshot({ path: path.join(__dirname, 'limely-planim-plan-bilgisi.png'), animations: 'disabled' });
    await page.keyboard.press('Escape');
    await page.locator('[data-date="2026-11-28"]').click();
    assert.equal(await page.locator('.record-pill').count(), 0);
    assert.equal(await page.locator('#selected-date').textContent(), '28 Kasım · Cumartesi');
    await page.locator('#open-review').click();
    assert.equal(await page.locator('#comparison-panel').getByText('Henüz kayıt yok', { exact: true }).count(), 5);
    assert.equal(await page.locator('.compare-macros').count(), 0);
    await page.keyboard.press('Escape');
    await page.getByRole('button', { name: 'Sonraki hafta', exact: true }).click();
    assert.equal(await page.locator('#empty-day').isVisible(), true);
    assert.equal(await page.locator('#review-card').isVisible(), false);
    await page.getByRole('button', { name: 'Bugüne dön', exact: true }).click();
    assert.equal(await page.locator('#meal-count').textContent(), '4 öğün');
    await page.locator('[data-meal="breakfast"]').click();
    assert.equal(await page.locator('#body-breakfast').isVisible(), true);
    assert.equal(await page.locator('.targets').textContent(), initialTargets, 'Inspecting recommendations does not edit targets.');
    assert.equal(await page.locator('#meal-list input,#meal-list select,#meal-list textarea').count(), 0);

    await open();
    for (const width of [320, 360, 390, 430]) {
      await page.setViewportSize({ width, height: 844 });
      const sizes = await page.evaluate(() => ({ viewport: innerWidth, content: document.querySelector('.page-scroll').scrollWidth, navBottom: document.querySelector('.bottom-nav').getBoundingClientRect().bottom, height: innerHeight }));
      assert.ok(sizes.content <= width, JSON.stringify(sizes));
      assert.ok(Math.abs(sizes.navBottom - sizes.height) < 1, 'Fixed navigation at ' + width);
      const overflow = await page.locator('.day-button,.targets,.dietitian-row,.meal-toggle,.review-button').evaluateAll(items => items.filter(i => i.scrollWidth > i.clientWidth + 1).map(i => i.className));
      assert.deepEqual(overflow, [], 'No component overflow at ' + width);
      await page.getByRole('button', { name: 'Plan bilgisini aç', exact: true }).click();
      const box = await page.locator('#info-dialog').boundingBox();
      assert.ok(box.x >= -1 && box.x + box.width <= width + 1);
      await page.keyboard.press('Escape');
      await page.locator('#open-review').click();
      const sheetOverflow = await page.locator('dialog[open] .sheet-header,dialog[open] .compare-tabs,dialog[open] .compare-totals,dialog[open] .compare-macros').evaluateAll(items => items.filter(i => i.scrollWidth > i.clientWidth + 1).map(i => i.className));
      assert.deepEqual(sheetOverflow, [], 'Comparison sheet fits ' + width);
      await page.keyboard.press('Escape');
    }
    await page.setViewportSize({ width: 1200, height: 2100 });
    await page.locator('#meal-lunch .alternative summary').click();
    await page.getByRole('button', { name: 'Sayfanın tamamını göster', exact: true }).click();
    await page.locator('.phone').screenshot({ path: path.join(__dirname, 'limely-planim-tam-sayfa.png'), animations: 'disabled' });
    assert.deepEqual(errors, []);
    assert.deepEqual(network, [], 'The design remains entirely local.');

    const board = await browser.newPage({ viewport: { width: 1050, height: 1230 }, deviceScaleFactor: 1.5 });
    await board.goto(local('limely-planim.html'));
    await board.setContent(`<!doctype html><html lang="tr"><head><meta charset="utf-8"><style>
      @font-face{font-family:Figtree;src:url('${brand('fontlar/figtree/figtree.ttf')}');font-weight:300 900}*{box-sizing:border-box}
      body{margin:0;background:#F8FAF2;color:#203B2F;font-family:Figtree,sans-serif}.board{padding:44px 72px 32px;background:radial-gradient(ellipse at 93% 0%,#EAF3DE 0%,transparent 36%)}
      header{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}header img{width:137px;height:48px;object-fit:contain}.tag{font-size:11px;letter-spacing:1.6px;font-weight:700}
      h1{font-size:35px;line-height:1.15;letter-spacing:-1px;margin:15px 0 10px;font-weight:750}.subtitle{font-size:15px;color:#657365;margin:0 0 29px}
      .screens{display:grid;grid-template-columns:390px 390px;justify-content:space-between;gap:40px}.label{font-size:11px;letter-spacing:1.5px;font-weight:700;color:#536b4c;margin:0 0 12px}
      .screen{display:block;width:390px;height:920px;border-radius:25px;border:1px solid #dae4d0;box-shadow:0 15px 35px #203b2f09}
      footer{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-top:22px;font-size:11px;color:#657365}.swatches{display:flex;gap:6px}.swatches span{width:17px;height:17px;border-radius:5px;border:1px solid #203b2f10}
    </style></head><body><div class="board"><header><img src="${brand('logolar/limely-yazili-logo-renkli.svg')}" alt="Limely"><span class="tag">MOBİL · PLANIM / 01</span></header><h1>Sana göre, her gün yanında.</h1><p class="subtitle">Diyetisyeninin hazırladığı plan, öğünlerin ve porsiyon alternatiflerin bir arada.</p><div class="screens"><section><p class="label">01 · PLAN VE HAFTALIK GÖRÜNÜM</p><img class="screen" src="${local('limely-planim-ilk-ekran.png')}" alt="Plan ve haftalık görünüm"></section><section><p class="label">02 · ÖĞÜNLER VE PORSİYONLAR</p><img class="screen" src="${local('limely-planim-devam.png')}" alt="Öğün ve porsiyon ayrıntıları"></section></div><footer><span>Figtree · Özgün Limely varlıkları · Örnek plan ve tüketim verileri</span><div class="swatches">${['#F8FAF2','#203B2F','#C9E879','#83B977','#F5D96A','#EAF3DE'].map(c => `<span style="background:${c}"></span>`).join('')}</div></footer></div></body></html>`);
    await board.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); });
    await board.screenshot({ path: path.join(__dirname, 'limely-planim.png'), fullPage: true });
    await board.close();
    const result = { passed:true, font:'Figtree', assetsLoaded:true, navigationOrder:true, viewportWidths:[320,360,390,430], dayAndWeekSelection:true, outsidePlanDateState:true, expandableMeals:true, alternativeGroupReadOnly:true, separatePlanAndActual:true, comparisonTabsAndKeyboard:true, dialogs:true, externalRequests:network.length, errors };
    fs.writeFileSync(path.join(__dirname, 'dogrulama.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result));
    console.log('Rendered: presentation, first screen, continuation, full page, plan info, consumption comparison.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
