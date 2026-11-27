// Extend the existing icon system without rebuilding any logo or mascot.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
let sharp;
try { sharp = require('sharp'); }
catch { sharp = require('C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1123-915-0_26.1123.915.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules/sharp'); }
const root = path.resolve(__dirname, '..');
const commit = '7981a0798a4f7184296bf42e94b6a8677f3ef2a0';
const names = { file: 'Dosya', send: 'Gönder', eye: 'Şifreyi göster', printer: 'Yazdır' };
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8').replace(/^\uFEFF/, ''));
const write = (file, value) => fs.writeFileSync(path.join(root, file), JSON.stringify(value, null, 2) + '\n');

(async () => {
  const original = read('source/korunan-varliklar-sha256.json');
  for (const [file, digest] of Object.entries(original)) assert.equal(hash(fs.readFileSync(path.join(root, file))), digest, file);
  const manifest = read('asset-manifest.json');
  const dependencies = read('source/dis-kaynaklar.json');
  for (const [name, title] of Object.entries(names)) {
    const sourceFile = `source/lucide/${name}.svg`;
    const source = fs.readFileSync(path.join(root, sourceFile), 'utf8');
    assert(source.includes('viewBox="0 0 24 24"'));
    const content = source.replace(/^[\s\S]*?<svg\b[^>]*>/, '').replace(/<\/svg>[\s\S]*$/, '').trim();
    const record = { url: `https://raw.githubusercontent.com/lucide-icons/lucide/${commit}/icons/${name}.svg`, file: sourceFile, sha256: hash(Buffer.from(source)) };
    const existing = dependencies.files.findIndex(row => row.file === sourceFile);
    if (existing === -1) dependencies.files.push(record); else dependencies.files[existing] = record;
    for (const [variant, color] of [['koyu', '#203B2F'], ['beyaz', '#FFFFFF']]) {
      const relative = `ikonlar/${variant}/${name}`;
      const svg = `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" role="img" aria-labelledby="asset-title"><title id="asset-title">${title} — ${variant}</title><g fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">\n${content}\n</g></svg>\n`;
      fs.writeFileSync(path.join(root, relative + '.svg'), svg);
      await sharp(Buffer.from(svg)).resize(96, 96).png().toFile(path.join(root, relative + '.png'));
      const asset = { id: relative.replaceAll('/', '-'), title: `${title} — ${variant}`, svg: relative + '.svg', png: relative + '.png', width: 96, height: 96, category: 'icon', source: `Lucide ${commit}; lisanslar/LUCIDE-LICENSE.txt`, opaque: false };
      const index = manifest.assets.findIndex(row => row.id === asset.id);
      if (index === -1) manifest.assets.push(asset); else manifest.assets[index] = asset;
    }
  }
  manifest.version = '1.2.0';
  manifest.dependencies = dependencies;
  write('source/dis-kaynaklar.json', dependencies);
  write('asset-manifest.json', manifest);
  console.log(JSON.stringify({ addedIcons: Object.keys(names), svgAndPngFiles: 16, protectedFilesVerified: Object.keys(original).length, version: manifest.version }));
})().catch(error => { console.error(error); process.exitCode = 1; });
