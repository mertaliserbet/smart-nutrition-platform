const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
let sharp;
try { sharp = require('sharp'); }
catch { sharp = require('C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1123-915-0_26.1123.915.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules/sharp'); }
const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'asset-manifest.json'), 'utf8'));

function label(text, x, y, size = 22, fill = '#203B2F', weight = 500) {
  return `<text x="${x}" y="${y}" fill="${fill}" font-family="Segoe UI,Arial,sans-serif" font-size="${size}" font-weight="${weight}">${text}</text>`;
}

async function main() {
  const report = [];
  for (const asset of manifest.assets) {
    const svg = fs.readFileSync(path.join(root, asset.svg), 'utf8');
    assert(!/<image\b|<script\b|<text\b|foreignObject|@font-face|data:image|href=/i.test(svg), `${asset.id}: non-vector or external dependency`);
    assert(/<(path|circle|ellipse|rect|line|polyline|polygon)\b/.test(svg) && svg.includes('viewBox='), `${asset.id}: missing shapes or viewBox`);
    const disk = await sharp(path.join(root, asset.png)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const rendered = await sharp(Buffer.from(svg)).resize({ width: disk.info.width }).ensureAlpha().raw().toBuffer();
    assert(disk.data.equals(rendered), `${asset.id}: PNG does not match SVG`);
    const alpha = await sharp(path.join(root, asset.png)).extractChannel(3).raw().toBuffer();
    let transparent = 0, opaque = 0, antialiased = 0;
    let minX = disk.info.width, minY = disk.info.height, maxX = 0, maxY = 0;
    for (let i = 0; i < alpha.length; i++) {
      if (!alpha[i]) transparent++;
      else {
        if (alpha[i] === 255) opaque++; else antialiased++;
        const x = i % disk.info.width, y = (i / disk.info.width) | 0;
        if (alpha[i] > 12) { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); }
      }
    }
    const minimumTransparentRatio = asset.category === 'decoration' ? 0.001 : 0.08;
    assert(transparent > alpha.length * minimumTransparentRatio && opaque > alpha.length * 0.002, `${asset.id}: alpha is not usable`);
    assert(antialiased > 12, `${asset.id}: antialiasing is missing`);
    assert(minX > 0 && minY > 0 && maxX < disk.info.width - 1 && maxY < disk.info.height - 1, `${asset.id}: clipped artwork`);
    report.push({ id: asset.id, width: disk.info.width, height: disk.info.height, hasTransparency: true, antialiasedPixels: antialiased, artworkBounds: [minX, minY, maxX, maxY], pngMatchesSvg: true, svgSha256: crypto.createHash('sha256').update(svg).digest('hex'), pngSha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, asset.png))).digest('hex') });
  }

  const W = 1600, H = 1160;
  let background = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="100%" height="100%" fill="#F8FAF2"/>`;
  background += label('LIMELY · SABİT LOGO VE MASKOT DOSYALARI', 60, 58, 28, '#203B2F', 700);
  background += label('Onaylı konseptten vektörleştirilmiş SVG + aynı çizimden şeffaf PNG', 60, 94, 21, '#627365');
  background += '<rect x="50" y="125" width="1500" height="270" rx="24" fill="#FFFFFF"/><rect x="50" y="420" width="1500" height="185" rx="24" fill="#203B2F"/>';
  background += label('Lime simgesi', 85, 166, 20) + label('Yazılı logo', 445, 166, 20);
  background += label('Koyu zemin · beyaz logo', 80, 460, 20, '#EAF3DE');
  background += label('DÖRT SABİT MASKOT POZU', 60, 660, 23, '#203B2F', 700);
  for (let i = 0; i < 4; i++) {
    background += `<rect x="${50 + i * 383}" y="685" width="351" height="370" rx="22" fill="#FFFFFF"/>`;
    background += label(['Merhaba', 'Göz kırpma', 'Su molası', 'Küçük kutlama'][i], 85 + i * 383, 1025, 22);
  }
  background += label('Logo yazısı fonta bağlı değil. SVG içinde bitmap yok. Tüm PNG dosyaları şeffaf.', 60, 1118, 21, '#627365');
  background += '</svg>';
  const placements = [
    ['logolar/limely-simge-renkli.svg', 220, 220, 145, 170],
    ['logolar/limely-yazili-logo-renkli.svg', 980, 210, 450, 185],
    ['logolar/limely-yazili-logo-beyaz.svg', 720, 140, 105, 462],
    ['logolar/limely-simge-beyaz.svg', 120, 120, 1300, 452],
    ...['merhaba', 'goz-kirpma', 'su-molasi', 'kutlama'].map((name, i) => [`maskotlar/limely-maskot-${name}.svg`, 330, 310, 61 + i * 383, 695]),
  ];
  const composites = [];
  for (const [file, width, height, left, top] of placements) composites.push({ input: await sharp(path.join(root, file), { density: 240 }).resize(width, height, { fit: 'inside' }).png().toBuffer(), left, top });
  await sharp(Buffer.from(background)).composite(composites).png().toFile(path.join(root, 'limely-paket-onizleme.png'));
  const expected = JSON.parse(fs.readFileSync(path.join(__dirname,'korunan-varliklar-sha256.json'),'utf8'));
  for (const [file,digest] of Object.entries(expected)) assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex'),digest,`Protected artwork changed: ${file}`);
  fs.writeFileSync(path.join(root, 'dogrulama.json'), JSON.stringify({ verified: true, protectedFilesVerified:Object.keys(expected).length, checks: [`${report.length} SVG are pure vector with no external dependencies`, `${report.length} PNG match their SVG render pixel for pixel`, 'All PNG include transparent and antialiased pixels', 'All artwork stays inside the canvas', 'The initial 20 logo and mascot files are unchanged'], assets: report }, null, 2) + '\n');
  console.log(JSON.stringify({ passed: report.length, svgAndPngMatch: true, transparency: true, preview: path.join(root, 'limely-paket-onizleme.png') }, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
