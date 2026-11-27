// Render the HTML itself and check its layout; no app/backend is started.
// node render-preview.cjs <directory containing the bundled node_modules>
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');
const packages = process.argv[2];
if (!packages) throw new Error('Pass the directory containing the bundled node_modules.');
const { chromium } = require(require.resolve('playwright', { paths: [packages] }));

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 1000 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', request => errors.push(request.url() + ': ' + request.failure().errorText));
    const url = pathToFileURL(path.join(__dirname, 'limely-gunum.html')).href;
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    await page.locator('.hero-mascot').waitFor();
    assert.deepEqual(await page.locator('.bottom-nav button').allTextContents(), ['Günüm', 'Ölçüm', 'Planım', 'Sohbet', 'Hesabım']);
    assert.equal(await page.evaluate(() => document.fonts.check('16px Figtree')), true);
    const broken = await page.locator('img').evaluateAll(images => images.filter(image => !image.complete || image.naturalWidth === 0).map(image => image.src));
    assert.deepEqual(broken, []);
    await page.locator('.phone').screenshot({ path: path.join(__dirname, 'limely-gunum.png'), animations: 'disabled' });
    await page.getByRole('button', { name: 'Atanmış öğün yok', exact: true }).click();
    assert.equal(await page.locator('#next-meal').isVisible(), false);
    await page.getByRole('button', { name: 'Atanmış öğün var', exact: true }).click();
    assert.equal(await page.locator('#next-meal').isVisible(), true);
    await page.locator('#water-add').click();
    assert.equal(await page.locator('#water-amount').textContent(), '1.000');
    assert.equal(await page.locator('#water-glasses').textContent(), '4');
    await page.goto(url + '?view=mobile');
    for (const width of [320, 360, 390, 430]) {
      await page.setViewportSize({ width, height: 844 });
      await page.evaluate(() => document.fonts.ready);
      const layout = await page.evaluate(() => {
        const phone = document.querySelector('.phone');
        const page = document.querySelector('.page-scroll');
        const nav = document.querySelector('.bottom-nav').getBoundingClientRect();
        return { width: phone.clientWidth, contentWidth: page.scrollWidth, navBottom: nav.bottom, viewport: innerHeight };
      });
      assert.ok(layout.contentWidth <= layout.width, JSON.stringify({ width, ...layout }));
      assert.ok(Math.abs(layout.navBottom - layout.viewport) < 1, 'Bottom navigation must remain at the viewport bottom.');
      const overflow = await page.locator('.entry-methods button, .water-copy, .water-tools, .energy-heading, .macro').evaluateAll(elements =>
        elements.filter(element => element.scrollWidth > element.clientWidth + 1).map(element => ({ class: element.className, width: element.clientWidth, content: element.scrollWidth })));
      assert.deepEqual(overflow, [], 'Component overflow at ' + width + ' px');
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: path.join(__dirname, 'limely-gunum-ilk-ekran.png'), animations: 'disabled' });
    await page.locator('.page-scroll').evaluate(element => element.scrollTop = element.scrollHeight);
    await page.screenshot({ path: path.join(__dirname, 'limely-gunum-devam.png'), animations: 'disabled' });
    assert.deepEqual(errors, []);
    console.log('PASS: assets, Figtree, navigation order, assigned-meal states, water preview, responsive overflow and fixed navigation at 320/360/390/430 px.');
    console.log('Rendered: limely-gunum.png, limely-gunum-ilk-ekran.png, limely-gunum-devam.png');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
