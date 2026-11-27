// Render and check only this local account design. No application/API access.
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
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', request => errors.push(request.url() + ': ' + request.failure().errorText));
    page.on('request', request => { if (/^https?:/.test(request.url())) external.push(request.url()); });
    async function decode() { await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); }); }
    async function open() { await page.goto(local('limely-hesabim.html')); await decode(); }
    async function shot(name) { await decode(); await page.screenshot({ path: output(name), animations: 'disabled' }); }
    const checkbox = name => page.locator(`#sharing-form [name="${name}"]`);
    const sharing = () => page.locator('.menu-row[data-dialog="sharing-dialog"]').click();

    await open();
    assert.equal(await page.evaluate(() => document.fonts.check('16px Figtree')), true);
    assert.deepEqual(await page.locator('.bottom-nav button').allTextContents(), ['Günüm', 'Ölçüm', 'Planım', 'Sohbet', 'Hesabım']);
    assert.equal(await page.locator('.bottom-nav [aria-current="page"]').textContent(), 'Hesabım');
    assert.equal(await page.locator('#profile-name').textContent(), 'Mert Ali Şerbet');
    assert.equal(await page.locator('.expert-copy strong').textContent(), 'Uğur Çetin');
    assert.equal(await page.locator('.menu-row').count(), 6);
    assert.deepEqual(await page.locator('.menu-section').first().locator('.menu-copy strong').allTextContents(), ['Günlük hedeflerim', 'Görevlerim', 'Cihaz sağlık verileri']);
    await shot('limely-hesabim-ilk-ekran.png');
    await page.locator('#page-scroll').evaluate(el => el.scrollTop = el.scrollHeight);
    await shot('limely-hesabim-devam.png');

    await page.getByRole('button', { name: 'Bilgilerimi gör', exact: false }).click();
    assert.equal(await page.locator('#profile-dialog input').count(), 0);
    assert.equal(await page.locator('#profile-dialog').getByText('mertaliserbet@example.com', { exact: true }).isVisible(), true);
    assert.equal(await page.locator('#profile-dialog').getByText('Doğrulandı', { exact: true }).isVisible(), true);
    await shot('limely-hesabim-bilgiler.png');
    await page.keyboard.press('Escape');

    await sharing();
    assert.equal(await checkbox('nutrition_plans').isChecked(), true);
    assert.equal(await checkbox('meal_logs').isChecked(), true);
    assert.equal(await checkbox('body_measurements').isChecked(), false);
    assert.equal(await checkbox('client_tasks').isChecked(), true);
    assert.equal(await checkbox('water_logs').isChecked(), false);
    assert.equal(await checkbox('water_logs').isDisabled(), true);
    await shot('limely-hesabim-paylasim.png');
    await checkbox('nutrition_plans').uncheck();
    assert.equal(await checkbox('meal_logs').isChecked(), true, 'Each category is independent');
    await page.keyboard.press('Escape');
    await sharing();
    assert.equal(await checkbox('nutrition_plans').isChecked(), true, 'Closing discards the unconfirmed draft');
    await checkbox('meal_logs').uncheck();
    await page.getByRole('button', { name: 'Tercihlerimi kaydet', exact: true }).click();
    assert.match(await page.locator('#toast').textContent(), /yalnız bu önizlemede/);
    await sharing();
    assert.equal(await checkbox('meal_logs').isChecked(), false);
    assert.equal(await checkbox('nutrition_plans').isChecked(), true);
    assert.equal(await checkbox('client_tasks').isChecked(), true);
    assert.equal(await checkbox('water_logs').isChecked(), false);
    await page.keyboard.press('Escape');

    await page.locator('.menu-row[data-dialog="security-dialog"]').click();
    assert.equal(await page.locator('#security-dialog input[type="password"]').count(), 0);
    assert.equal(await page.locator('#security-dialog').getByText('E-posta doğrulandı', { exact: true }).isVisible(), true);
    await shot('limely-hesabim-guvenlik.png');
    await page.keyboard.press('Escape');
    await page.locator('.professional-card .text-action').click();
    assert.equal(await page.locator('#professional-dialog .step').count(), 3);
    assert.match(await page.locator('#professional-dialog .sheet-intro').textContent(), /aynı hesabınla/i);
    assert.match(await page.locator('#professional-dialog .sheet-intro').textContent(), /onaylandıktan sonra/);
    await shot('limely-hesabim-diyetisyen.png');
    await page.getByRole('button', { name: 'Başvuruya geç', exact: true }).click();
    assert.equal(context.pages().length, 1, 'No external panel, token transfer or new account');
    assert.equal(page.url(), local('limely-hesabim.html'));
    await page.locator('.logout').click();
    assert.equal(await page.locator('#logout-dialog').getByRole('button', { name: 'Vazgeç', exact: true }).evaluate(el => el === document.activeElement), true);
    await shot('limely-hesabim-cikis.png');
    await page.getByRole('button', { name: 'Vazgeç', exact: true }).click();
    assert.equal(await page.locator('#logout-dialog').isVisible(), false);
    await page.locator('.logout').click();
    await page.locator('#confirm-logout').click();
    assert.match(await page.locator('#toast').textContent(), /gerçek oturum kapatılmadı/);

    for (const width of [320, 360, 390, 430]) {
      await open(); await page.setViewportSize({ width, height: 844 });
      const overflow = await page.locator('.phone,.page-scroll,.profile-main,.profile-footer,.dietitian-row,.menu-row,.professional-top,.bottom-nav').evaluateAll(rows => rows.filter(el => el.scrollWidth > el.clientWidth + 1).map(el => el.className));
      assert.deepEqual(overflow, [], 'No content overflow at ' + width);
      const nav = await page.locator('.bottom-nav').boundingBox();
      assert.ok(Math.abs(nav.y + nav.height - 844) < 1, 'Fixed navigation at ' + width);
      for (const id of ['profile-dialog', 'sharing-dialog', 'security-dialog', 'professional-dialog', 'about-dialog', 'logout-dialog']) {
        await page.evaluate(id => document.querySelector(`[data-dialog="${id}"]`).click(), id);
        const box = await page.locator('#' + id).boundingBox();
        assert.ok(box.x >= -1 && box.x + box.width <= width + 1 && box.y >= -1 && box.y + box.height <= 845, id + ' fits ' + width);
        const sheetOverflow = await page.locator('#' + id + ' .sheet-body').evaluate(el => el.scrollWidth > el.clientWidth + 1);
        assert.equal(sheetOverflow, false, id + ' does not overflow');
        await page.keyboard.press('Escape');
      }
      await sharing();
      await page.keyboard.press('Escape');
      assert.equal(await page.locator('.menu-row[data-dialog="sharing-dialog"]').evaluate(el => document.activeElement === el), true);
    }
    await open(); await page.setViewportSize({ width: 320, height: 520 });
    await page.getByRole('button', { name: 'Bilgilerimi gör', exact: false }).click();
    assert.equal(await page.locator('#profile-dialog .primary').isVisible(), true);
    await page.keyboard.press('Escape');
    await page.setViewportSize({ width: 1200, height: 1900 });
    await page.locator('#preview-full').click();
    await page.locator('.phone').screenshot({ path: output('limely-hesabim-tam-sayfa.png'), animations: 'disabled' });
    assert.deepEqual(errors, []); assert.deepEqual(external, []);

    const board = await browser.newPage({ viewport: { width: 1050, height: 1230 }, deviceScaleFactor: 1.5 });
    await board.goto(local('limely-hesabim.html'));
    await board.setContent(`<!doctype html><html lang="tr"><meta charset="utf-8"><style>
      @font-face{font-family:Figtree;src:url('${brand('fontlar/figtree/figtree.ttf')}');font-weight:300 900}*{box-sizing:border-box}body{margin:0;color:#203B2F;background:#F8FAF2;font-family:Figtree,sans-serif}.board{padding:44px 72px 32px;background:radial-gradient(ellipse at 93% 0%,#EAF3DE,transparent 36%)}header{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}header img{width:137px;height:48px;object-fit:contain}.tag{font-size:11px;letter-spacing:1.6px;font-weight:700}h1{font-size:35px;line-height:1.15;letter-spacing:-1px;margin:15px 0 10px;font-weight:750}.subtitle{font-size:15px;color:#657365;margin:0 0 29px}.screens{display:grid;grid-template-columns:390px 390px;justify-content:space-between;gap:40px}.label{font-size:11px;letter-spacing:1.5px;font-weight:700;color:#536b4c;margin:0 0 12px}.screen{display:block;width:390px;height:920px;border-radius:25px;border:1px solid #dae4d0;box-shadow:0 15px 35px #203b2f09}footer{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-top:22px;font-size:11px;color:#657365}.swatches{display:flex;gap:6px}.swatches span{width:17px;height:17px;border-radius:5px;border:1px solid #203b2f10}
      </style><div class="board"><header><img src="${brand('logolar/limely-yazili-logo-renkli.svg')}" alt="Limely"><span class="tag">MOBİL · HESABIM / 01</span></header><h1>Kendine iyi gelen alanın.</h1><p class="subtitle">Profilin, diyetisyenin ve paylaşım tercihlerin. Aynı sıcak Limely diliyle.</p><div class="screens"><section><p class="label">01 · PROFİL VE GÜNLÜK TAKİP</p><img class="screen" src="${local('limely-hesabim-ilk-ekran.png')}" alt="Hesabım ekranının üst görünümü"></section><section><p class="label">02 · GİZLİLİK VE HESAP SEÇENEKLERİ</p><img class="screen" src="${local('limely-hesabim-devam.png')}" alt="Hesap menüsü devamı"></section></div><footer><span>Figtree · Özgün maskot ve ikonlar · Örnek hesap bilgileri</span><div class="swatches">${['#F8FAF2','#203B2F','#C9E879','#83B977','#F5D96A','#EAF3DE'].map(color => `<span style="background:${color}"></span>`).join('')}</div></footer></div>`);
    await board.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); });
    await board.screenshot({ path: output('limely-hesabim.png'), fullPage: true });
    await board.close();
    const result = { passed: true, font: 'Figtree', existingBrandAssetsOnly: true, navigationOrder: true, widths: [320, 360, 390, 430], compactHeight: 520, readOnlyAccountDetails: true, independentSharingCategories: true, cancelDiscardsPermissionDraft: true, waterSharingDisabled: true, securitySheet: true, sameAccountExpertEntry: true, logoutConfirmationOnly: true, dialogsAndFocusReturn: true, externalRequests: external.length, errors };
    fs.writeFileSync(output('dogrulama.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
