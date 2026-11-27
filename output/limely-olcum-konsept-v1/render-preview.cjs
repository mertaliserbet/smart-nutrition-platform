// Render the local HTML only. No app, API, account or database is accessed.
// node render-preview.cjs <directory containing node_modules>
const path = require('node:path');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');
const packages = process.argv[2];
if (!packages) throw new Error('Pass the directory containing the bundled node_modules.');
const { chromium } = require(require.resolve('playwright', { paths: [packages] }));
const local = filename => pathToFileURL(path.join(__dirname, filename)).href;
const asset = filename => pathToFileURL(path.join(__dirname, '../limely-marka-paketi-v1', filename)).href;

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 920 }, deviceScaleFactor: 2, reducedMotion: 'reduce', timezoneId: 'Europe/Istanbul' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', request => errors.push(request.url() + ': ' + request.failure().errorText));
    const open = async () => {
      await page.goto(local('limely-olcum.html'));
      await page.evaluate(() => document.fonts.ready);
      assert.deepEqual(await page.locator('img').evaluateAll(images => images.filter(i => !i.complete || i.naturalWidth === 0).map(i => i.src)), [], 'Every existing brand asset must load.');
    };
    await open();
    assert.equal(await page.evaluate(() => document.fonts.check('16px Figtree')), true);
    assert.deepEqual(await page.locator('.bottom-nav button').allTextContents(), ['Günüm', 'Ölçüm', 'Planım', 'Sohbet', 'Hesabım']);
    assert.equal(await page.locator('[aria-current="page"]').textContent(), 'Ölçüm');
    assert.equal(await page.locator('#latest-weight').textContent(), '72,4');
    assert.equal(await page.locator('#history-list details').count(), 3);
    await page.screenshot({ path: path.join(__dirname, 'limely-olcum-ilk-ekran.png'), animations: 'disabled' });
    await page.locator('.page-scroll').evaluate(el => { const section = document.querySelector('.measures'); el.scrollTop += section.getBoundingClientRect().top - el.getBoundingClientRect().top - 22; });
    await page.screenshot({ path: path.join(__dirname, 'limely-olcum-devam.png'), animations: 'disabled' });
    await page.locator('.page-scroll').evaluate(el => el.scrollTop = 0);
    await page.getByRole('button', { name: 'Yeni ölçüm ekle', exact: true }).click();
    await page.screenshot({ path: path.join(__dirname, 'limely-olcum-yeni-kayit.png'), animations: 'disabled' });
    await page.getByRole('button', { name: 'Ölçümümü kaydet', exact: true }).click();
    assert.equal(await page.getByRole('alert').textContent(), 'En az bir ölçüm alanını doldur.');
    await page.getByRole('textbox', { name: /^Kilo/ }).fill('72,2');
    await page.getByRole('button', { name: 'Ölçümümü kaydet', exact: true }).click();
    assert.equal(await page.locator('#latest-weight').textContent(), '72,2');
    await page.locator('.history-row').first().locator('summary').click();
    assert.equal(await page.locator('.history-row').first().getByText('Belirtilmedi', { exact: true }).count(), 4, 'Missing values stay missing.');
    await open();
    await page.getByRole('button', { name: '7 gün', exact: true }).click();
    assert.equal(await page.locator('#chart-meta').textContent(), 'Son 7 gün · 2 ölçüm');
    await page.getByLabel('Grafikte gösterilen ölçüm', { exact: true }).selectOption('waistCm');
    assert.equal(await page.locator('#chart-last').textContent(), '82,0 cm');
    await page.getByRole('button', { name: 'Tümünü gör', exact: true }).click();
    assert.equal(await page.locator('#history-list details').count(), 6);
    await page.locator('.history-row').first().locator('summary').click();
    assert.equal(await page.locator('.history-row').first().getByText('82,0 cm', { exact: true }).isVisible(), true);
    await open();
    for (const width of [320, 360, 390, 430]) {
      await page.setViewportSize({ width, height: 844 });
      const geometry = await page.evaluate(() => {
        const scroll = document.querySelector('.page-scroll');
        const nav = document.querySelector('.bottom-nav').getBoundingClientRect();
        const hero = document.querySelector('.hero-copy').getBoundingClientRect();
        return { width: innerWidth, contentWidth: scroll.scrollWidth, navBottom: nav.bottom, height: innerHeight, heroRight: hero.right };
      });
      assert.ok(geometry.contentWidth <= width, JSON.stringify(geometry));
      assert.ok(Math.abs(geometry.navBottom - geometry.height) < 1, 'Bottom menu remains fixed at ' + width);
      await page.getByRole('button', { name: 'Yeni ölçüm ekle', exact: true }).click();
      const dialog = await page.locator('dialog').boundingBox();
      assert.ok(dialog.x >= -1 && dialog.x + dialog.width <= width + 1, 'Form fits ' + width);
      await page.keyboard.press('Escape');
    }
    await page.setViewportSize({ width: 1200, height: 1800 });
    await page.getByRole('button', { name: 'Sayfanın tamamını göster', exact: true }).click();
    await page.locator('.phone').screenshot({ path: path.join(__dirname, 'limely-olcum-tam-sayfa.png'), animations: 'disabled' });
    assert.deepEqual(errors, []);

    const board = await browser.newPage({ viewport: { width: 1050, height: 1150 }, deviceScaleFactor: 1.5 });
    await board.goto(local('limely-olcum.html'));
    await board.setContent(`<!doctype html><html lang="tr"><head><meta charset="utf-8"><style>
      @font-face{font-family:Figtree;src:url('${asset('fontlar/figtree/figtree.ttf')}');font-weight:300 900}
      *{box-sizing:border-box}body{margin:0;background:#F8FAF2;color:#203B2F;font-family:Figtree,sans-serif}
      .board{padding:44px 72px 32px;min-height:1150px;background:radial-gradient(ellipse at 93% 0%,#EAF3DE 0%,transparent 36%)}
      header{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}header img{width:137px;height:48px;object-fit:contain}
      .tag{font-size:11px;letter-spacing:1.6px;font-weight:700}h1{font-size:35px;letter-spacing:-1px;line-height:1.15;margin:15px 0 10px;font-weight:750}
      .subtitle{font-size:15px;color:#657365;margin:0 0 29px}.screens{display:grid;grid-template-columns:390px 390px;justify-content:space-between;gap:40px}
      .label{font-size:11px;letter-spacing:1.5px;font-weight:700;margin:0 0 12px;color:#536b4c}.screen{display:block;width:390px;height:920px;border-radius:25px;border:1px solid #dae4d0;box-shadow:0 15px 35px #203b2f09}
      footer{display:flex;align-items:center;justify-content:space-between;margin-top:22px;font-size:11px;color:#657365}.swatches{display:flex;gap:6px}.swatches span{width:17px;height:17px;border-radius:5px;border:1px solid #203b2f10}
    </style></head><body><div class="board"><header><img src="${asset('logolar/limely-yazili-logo-renkli.svg')}" alt="Limely"><span class="tag">MOBİL · ÖLÇÜM / 01</span></header><h1>Değişimin, kendi ritminde.</h1><p class="subtitle">Son ölçümün, küçük adımların ve zaman içindeki değişimin bir arada.</p><div class="screens"><section><p class="label">01 · SON ÖLÇÜM VE DEĞİŞİM</p><img class="screen" src="${local('limely-olcum-ilk-ekran.png')}" alt="Ölçüm sayfasının üst bölümü"></section><section><p class="label">02 · VÜCUT ÖLÇÜLERİ VE GEÇMİŞ</p><img class="screen" src="${local('limely-olcum-devam.png')}" alt="Ölçüm sayfasının devamı"></section></div><footer><span>Figtree · Özgün Limely maskotu ve ikonları · Örnek veriler</span><div class="swatches">${['#F8FAF2','#203B2F','#C9E879','#83B977','#F5D96A','#EAF3DE'].map(c=>`<span style="background:${c}"></span>`).join('')}</div></footer></div></body></html>`);
    await board.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); });
    await board.screenshot({ path: path.join(__dirname, 'limely-olcum.png'), fullPage: true });
    await board.close();
    const result = { passed:true, font:'Figtree', assetsLoaded:true, navigationOrder:true, viewportWidths:[320,360,390,430], periodsAndMetrics:true, expandableHistory:true, formAndDecimalComma:true, missingValuesPreserved:true, pageErrors:errors };
    fs.writeFileSync(path.join(__dirname, 'dogrulama.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result));
    console.log('Rendered: limely-olcum.png, first screen, continuation, full page, new measurement form.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
