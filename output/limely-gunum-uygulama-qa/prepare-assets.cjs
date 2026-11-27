// Rasterize the approved SVG icons and HTML plate composition for Flutter.
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const packages = process.argv[2];
if (!packages) throw new Error('Bundled node_modules directory is required.');
const sharp = require(require.resolve('sharp', { paths: [packages] }));
const { chromium } = require(require.resolve('playwright', { paths: [packages] }));
const root = path.resolve(__dirname, '../..');
const assets = path.join(root, 'mobile/assets/limely');
const concept = path.join(root, 'output/limely-gunum-konsept-v1');
(async () => {
  for (const [input, variant, name] of [['camera-light', 'beyaz', 'camera'], ['image', 'koyu', 'image'], ['barcode', 'koyu', 'barcode']]) {
    await sharp(path.join(concept, 'assets', input + '.svg')).resize(96, 96).png().toFile(path.join(assets, 'ikonlar', variant, name + '.png'));
  }
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 430, height: 900 }, deviceScaleFactor: 3, reducedMotion: 'reduce' });
    await page.goto(pathToFileURL(path.join(concept, 'limely-gunum.html')).href);
    await page.locator('.meal-art img').evaluate(image => image.decode());
    await page.evaluate(() => {
      const art = document.querySelector('.meal-art');
      document.body.replaceChildren(art);
      document.body.style.background = 'transparent';
      document.documentElement.style.background = 'transparent';
      Object.assign(art.style, { position: 'relative', zIndex: '0', width: '230px', height: '190px' });
    });
    await page.locator('.meal-art').screenshot({ path: path.join(assets, 'gorseller/limely-ogun-tabagi.png'), omitBackground: true });
  } finally { await browser.close(); }
  console.log('Prepared 3 icon PNGs and the approved HTML plate composition.');
})().catch(error => { console.error(error); process.exitCode = 1; });
