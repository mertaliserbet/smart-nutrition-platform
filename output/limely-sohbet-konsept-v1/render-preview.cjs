// Render and exercise the local design only. No app, API, credentials or DB.
// node render-preview.cjs <directory containing the bundled node_modules>
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');
const packages = process.argv[2];
if (!packages) throw new Error('Pass the bundled node_modules directory.');
const { chromium } = require(require.resolve('playwright', { paths: [packages] }));
const local = name => pathToFileURL(path.join(__dirname, name)).href;
const brand = name => pathToFileURL(path.join(__dirname, '../limely-marka-paketi-v1', name)).href;
const output = name => path.join(__dirname, name);
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 920 }, deviceScaleFactor: 2, timezoneId: 'Europe/Istanbul', reducedMotion: 'reduce' });
    const page = await context.newPage();
    const errors = [], external = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('requestfailed', r => errors.push(r.url() + ': ' + r.failure().errorText));
    page.on('request', r => { if (/^https?:/.test(r.url())) external.push(r.url()); });
    async function decode() { await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); }); }
    async function open() { await page.goto(local('limely-sohbet.html')); await decode(); }
    async function screenshot(name) { await decode(); await page.screenshot({ path: output(name), animations: 'disabled' }); }
    await open();
    assert.equal(await page.evaluate(() => document.fonts.check('16px Figtree')), true);
    assert.deepEqual(await page.locator('.bottom-nav button').allTextContents(), ['Günüm', 'Ölçüm', 'Planım', 'Sohbet', 'Hesabım']);
    assert.equal(await page.locator('.bottom-nav [aria-current="page"]').textContent(), 'Sohbet');
    assert.equal(await page.locator('.message').count(), 4);
    assert.equal(await page.locator('#send-message').isDisabled(), true);
    await screenshot('limely-sohbet-ilk-ekran.png');
    await page.locator('#page-scroll').evaluate(el => el.scrollTop = el.scrollHeight);
    await screenshot('limely-sohbet-devam.png');
    await page.getByRole('button', { name: 'haftalik-plan.pdf dosyasını görüntüle', exact: true }).click();
    assert.equal(await page.locator('#sample-document').isVisible(), true);
    await screenshot('limely-sohbet-dosya-onizleme.png');
    await page.keyboard.press('Escape');
    await page.getByRole('button', { name: 'Dosya ekle', exact: true }).click();
    await screenshot('limely-sohbet-dosya-paylasimi.png');
    await page.getByRole('button', { name: 'Planımdan paylaş', exact: false }).click();
    assert.equal(await page.locator('#pending-file').isVisible(), true);
    assert.equal(await page.locator('#send-message').isEnabled(), true);
    await page.getByRole('button', { name: 'Ekli dosyayı kaldır', exact: true }).click();
    assert.equal(await page.locator('#send-message').isDisabled(), true);
    const sample = '<img src=x onerror=alert(1)> i ı İ I ş Ş ö Ö ü Ü ğ Ğ ç Ç';
    await page.getByRole('textbox', { name: "Uğur'a mesajın", exact: true }).fill(sample);
    await page.getByRole('button', { name: 'Mesajı gönder', exact: true }).click();
    assert.equal(await page.locator('.message.mine').last().locator('.bubble p').textContent(), sample);
    assert.equal(await page.locator('.message.mine').last().locator('.bubble img').count(), 0);
    assert.equal(await page.locator('.preview-message-label').last().textContent(), 'Önizleme mesajı');
    assert.equal(await page.locator('#message-input').inputValue(), '');
    await page.locator('#message-input').fill('Birinci satır');
    await page.locator('#message-input').press('Shift+Enter');
    await page.locator('#message-input').press('x');
    assert.equal(await page.locator('#message-input').inputValue(), 'Birinci satır\nx');
    const beforeEnter = await page.locator('.message').count();
    await page.locator('#message-input').press('Enter');
    assert.equal(await page.locator('.message').count(), beforeEnter + 1);
    // Only a filename is shown; no reader, upload, storage or network is used.
    await page.locator('#file-input').setInputFiles({ name: 'ornek-ŞİÖ.pdf', mimeType: 'application/pdf', buffer: Buffer.from('synthetic preview') });
    assert.equal(await page.locator('#pending-file-name').textContent(), 'ornek-ŞİÖ.pdf');
    await page.locator('#send-message').click();
    await page.getByRole('button', { name: 'ornek-ŞİÖ.pdf dosyasını görüntüle', exact: true }).click();
    assert.equal(await page.locator('#sample-document').isVisible(), false);
    await page.keyboard.press('Escape');
    await open();
    // Preview controls are available outside the phone on desktop.
    await page.evaluate(() => document.querySelector('#preview-empty').click());
    assert.equal(await page.locator('#empty-state').isVisible(), true);
    await screenshot('limely-sohbet-yeni-sohbet.png');
    await page.getByRole('button', { name: 'Merhaba diyelim', exact: true }).click();
    assert.equal(await page.locator('#message-input').inputValue(), 'Merhaba Uğur, nasılsın?');
    await page.locator('#send-message').click();
    assert.equal(await page.locator('#empty-state').isVisible(), false);
    assert.equal(await page.locator('.message').count(), 1);
    for (const width of [320, 360, 390, 430]) {
      await open(); await page.setViewportSize({ width, height: 844 });
      const overflow = await page.locator('.phone,.page-scroll,.expert-card,.composer-controls,.bottom-nav,.message,.file-card').evaluateAll(items => items.filter(i => i.scrollWidth > i.clientWidth + 1).map(i => i.className));
      assert.deepEqual(overflow, [], 'No overflow at ' + width);
      const nav = await page.locator('.bottom-nav').boundingBox();
      assert.ok(Math.abs(nav.y + nav.height - 844) < 1, 'Navigation stays at bottom');
      const input = await page.locator('.composer').boundingBox();
      assert.ok(input.y + input.height <= nav.y + 1, 'Composer stays above navigation');
      await page.locator('#open-expert').click();
      assert.equal(await page.locator('#expert-dialog').getByText('Uğur Çetin', { exact: true }).isVisible(), true);
      await page.keyboard.press('Escape');
      await page.locator('#open-attachment').click();
      const sheet = await page.locator('#attachment-dialog').boundingBox();
      assert.ok(sheet.x >= -1 && sheet.x + sheet.width <= width + 1);
      await page.keyboard.press('Escape');
      assert.equal(await page.locator('#open-attachment').evaluate(el => document.activeElement === el), true);
    }
    await open(); await page.setViewportSize({ width: 320, height: 520 });
    const compactComposer = await page.locator('#message-input').boundingBox();
    assert.ok(compactComposer.y >= 0 && compactComposer.y + compactComposer.height <= 520, 'Composer fits a short viewport');
    await page.setViewportSize({ width: 1200, height: 1600 });
    await page.locator('#preview-full').click();
    await page.locator('.phone').screenshot({ path: output('limely-sohbet-tam-sayfa.png'), animations: 'disabled' });
    assert.deepEqual(errors, []); assert.deepEqual(external, []);
    const board = await browser.newPage({ viewport: { width: 1050, height: 1230 }, deviceScaleFactor: 1.5 });
    await board.goto(local('limely-sohbet.html'));
    await board.setContent(`<!doctype html><html lang="tr"><meta charset="utf-8"><style>
      @font-face{font-family:Figtree;src:url('${brand('fontlar/figtree/figtree.ttf')}');font-weight:300 900}*{box-sizing:border-box}body{margin:0;color:#203B2F;background:#F8FAF2;font-family:Figtree,sans-serif}.board{padding:44px 72px 32px;background:radial-gradient(ellipse at 93% 0%,#EAF3DE,transparent 36%)}header{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}header img{width:137px;height:48px;object-fit:contain}.tag{font-size:11px;letter-spacing:1.6px;font-weight:700}h1{font-size:35px;line-height:1.15;letter-spacing:-1px;margin:15px 0 10px;font-weight:750}.subtitle{font-size:15px;color:#657365;margin:0 0 29px}.screens{display:grid;grid-template-columns:390px 390px;justify-content:space-between;gap:40px}.label{font-size:11px;letter-spacing:1.5px;font-weight:700;color:#536b4c;margin:0 0 12px}.screen{display:block;width:390px;height:920px;border-radius:25px;border:1px solid #dae4d0;box-shadow:0 15px 35px #203b2f09}footer{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-top:22px;font-size:11px;color:#657365}.swatches{display:flex;gap:6px}.swatches span{width:17px;height:17px;border-radius:5px;border:1px solid #203b2f10}
      </style><div class="board"><header><img src="${brand('logolar/limely-yazili-logo-renkli.svg')}" alt="Limely"><span class="tag">MOBİL · SOHBET / 01</span></header><h1>Bir mesaj, birlikte bir adım.</h1><p class="subtitle">Diyetisyeninle sıcak ve sade bir iletişim. Aynı renkler, aynı Limely.</p><div class="screens"><section><p class="label">01 · SOHBETE MERHABA</p><img class="screen" src="${local('limely-sohbet-ilk-ekran.png')}" alt="Sohbet ekranının üst görünümü"></section><section><p class="label">02 · İLK MESAJ / BOŞ DURUM</p><img class="screen" src="${local('limely-sohbet-yeni-sohbet.png')}" alt="İlk mesaj ve boş sohbet görünümü"></section></div><footer><span>Figtree · Özgün maskot ve ikonlar · Örnek yazışma</span><div class="swatches">${['#F8FAF2','#203B2F','#C9E879','#83B977','#F5D96A','#EAF3DE'].map(c => `<span style="background:${c}"></span>`).join('')}</div></footer></div>`);
    await board.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); });
    await board.screenshot({ path: output('limely-sohbet.png'), fullPage: true });
    await board.close();
    const icons = await browser.newPage({ viewport: { width: 1120, height: 790 }, deviceScaleFactor: 1.5 });
    await icons.goto(brand('ikonlar/ek-ikonlar.html'));
    await icons.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); });
    assert.equal(await icons.locator('.card').count(), 4);
    await icons.screenshot({ path: path.join(__dirname, '../limely-marka-paketi-v1/limely-ek-ikonlar.png'), fullPage: true });
    await icons.close();
    const result = { passed: true, font: 'Figtree', originalBrandAssets: true, navigationOrder: true, widths: [320, 360, 390, 430], compactHeight: 520, composerAboveNavigation: true, emptyState: true, textAndUnicodeInput: true, safeTextRendering: true, enterAndShiftEnter: true, attachmentPreviewOnly: true, accessibleDialogs: true, newIcons: ['file', 'send', 'eye', 'printer'], externalRequests: external.length, errors };
    fs.writeFileSync(output('dogrulama.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
