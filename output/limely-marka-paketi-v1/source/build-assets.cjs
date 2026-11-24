/* Reproducible vector tracing of the approved Limely concept board.
 * No application code, fonts, network resources or generated replacements.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
let sharp;
try { sharp = require('sharp'); }
catch { sharp = require('C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1123-915-0_26.1123.915.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules/sharp'); }

const root = path.resolve(__dirname, '..');
const sourcePath = path.join(__dirname, 'onayli-konsept.png');
const palette = {
  background: '#F8FAF2', ink: '#203B2F', lime: '#C9E879',
  body: '#83B977', leaf: '#3D7756', yellow: '#F5D96A', soft: '#EAF3DE',
};
const escape = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

function foreground(r, g, b) {
  return (g - r > 9 && g - b > 19) ||
    (r < 165 && g < 190 && b < 165) ||
    (r > 175 && g > 145 && b < 179) ||
    (b - r > 10 && g - r > 14 && b > g - 9 && g > 125);
}

function fillHoles(input, width, height) {
  const outside = new Uint8Array(input.length);
  const stack = [];
  const add = i => { if (!input[i] && !outside[i]) { outside[i] = 1; stack.push(i); } };
  for (let x = 0; x < width; x++) { add(x); add((height - 1) * width + x); }
  for (let y = 0; y < height; y++) { add(y * width); add(y * width + width - 1); }
  while (stack.length) {
    const i = stack.pop(), x = i % width, y = (i / width) | 0;
    if (x) add(i - 1);
    if (x + 1 < width) add(i + 1);
    if (y) add(i - width);
    if (y + 1 < height) add(i + width);
  }
  return Uint8Array.from(input, (_, i) => outside[i] ? 0 : 1);
}

function area(points) {
  let a = 0;
  for (let i = 0; i < points.length; i++) {
    const p = points[i], q = points[(i + 1) % points.length];
    a += p[0] * q[1] - q[0] * p[1];
  }
  return a / 2;
}

function simplify(points, tolerance) {
  if (points.length < 4) return points;
  const sq = tolerance * tolerance;
  const dist = (p, a, b) => {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const t = dx || dy ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy))) : 0;
    return (p[0] - a[0] - t * dx) ** 2 + (p[1] - a[1] - t * dy) ** 2;
  };
  function rdp(list) {
    let max = sq, at = -1;
    for (let i = 1; i < list.length - 1; i++) {
      const d = dist(list[i], list[0], list[list.length - 1]);
      if (d > max) { max = d; at = i; }
    }
    if (at < 0) return [list[0], list[list.length - 1]];
    return [...rdp(list.slice(0, at + 1)).slice(0, -1), ...rdp(list.slice(at))];
  }
  let pivot = 0, farthest = 0;
  for (let i = 1; i < points.length; i++) {
    const d = (points[i][0] - points[0][0]) ** 2 + (points[i][1] - points[0][1]) ** 2;
    if (d > farthest) { farthest = d; pivot = i; }
  }
  return [...rdp(points.slice(0, pivot + 1)).slice(0, -1), ...rdp([...points.slice(pivot), points[0]]).slice(0, -1)];
}

const n = value => Math.round(value * 100) / 100;
function curve(points) {
  if (points.length < 3) return '';
  let d = `M${n(points[0][0])} ${n(points[0][1])}`;
  for (let i = 0; i < points.length; i++) {
    const a = points[(i + points.length - 1) % points.length], b = points[i];
    const c = points[(i + 1) % points.length], e = points[(i + 2) % points.length];
    d += `C${n(b[0] + (c[0] - a[0]) / 7)} ${n(b[1] + (c[1] - a[1]) / 7)} ${n(c[0] - (e[0] - b[0]) / 7)} ${n(c[1] - (e[1] - b[1]) / 7)} ${n(c[0])} ${n(c[1])}`;
  }
  return d + 'Z';
}

function trace(mask, width, height, minArea = 2.4, tolerance = 0.7) {
  const edges = [], outgoing = new Map();
  const key = (x, y) => y * (width + 1) + x;
  const add = (x1, y1, x2, y2, dir) => {
    const id = edges.length, k = key(x1, y1);
    edges.push({ start: [x1, y1], end: [x2, y2], dir, used: false });
    if (!outgoing.has(k)) outgoing.set(k, []);
    outgoing.get(k).push(id);
  };
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const i = y * width + x;
    if (!mask[i]) continue;
    if (!y || !mask[i - width]) add(x, y, x + 1, y, 0);
    if (x === width - 1 || !mask[i + 1]) add(x + 1, y, x + 1, y + 1, 1);
    if (y === height - 1 || !mask[i + width]) add(x + 1, y + 1, x, y + 1, 2);
    if (!x || !mask[i - 1]) add(x, y + 1, x, y, 3);
  }
  const loops = [];
  for (let start = 0; start < edges.length; start++) {
    if (edges[start].used) continue;
    const points = []; let id = start;
    while (!edges[id].used) {
      const edge = edges[id]; edge.used = true; points.push(edge.start);
      const candidates = (outgoing.get(key(...edge.end)) || []).filter(i => !edges[i].used);
      if (!candidates.length) break;
      const rank = turn => ({ 1: 0, 0: 1, 3: 2, 2: 3 })[turn];
      candidates.sort((a, b) => rank((edges[a].dir - edge.dir + 4) % 4) - rank((edges[b].dir - edge.dir + 4) % 4));
      id = candidates[0];
    }
    if (Math.abs(area(points)) >= minArea) {
      // Smooth the source pixel staircase before fitting editable Bezier paths.
      let smooth = points;
      for (let pass = 0; pass < 3; pass++) smooth = smooth.map((_, j) => {
        const weights = [1, 4, 6, 4, 1];
        let x = 0, y = 0;
        for (let k = -2; k <= 2; k++) {
          const p = smooth[(j + k + smooth.length) % smooth.length];
          x += p[0] * weights[k + 2]; y += p[1] * weights[k + 2];
        }
        return [x / 16, y / 16];
      });
      loops.push(simplify(smooth, Math.max(tolerance, 0.65)));
    }
  }
  return loops.map(curve).join('');
}

const shape = (d, fill, extra = '') => d ? `<path fill="${fill}" fill-rule="evenodd" d="${d}"${extra}/>` : '';
const defs = `<defs>
  <linearGradient id="body" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8DBB78"/><stop offset=".52" stop-color="#88B975"/><stop offset="1" stop-color="#7FB16B"/></linearGradient>
  <linearGradient id="fruit" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#C4E176"/><stop offset="1" stop-color="#BDDC71"/></linearGradient>
  <linearGradient id="leaf" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#477F58"/><stop offset="1" stop-color="#3A7550"/></linearGradient>
  <linearGradient id="rind" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#3E8452"/><stop offset="1" stop-color="#438C58"/></linearGradient>
  <linearGradient id="yellow" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#F9DA70"/><stop offset="1" stop-color="#F8D25C"/></linearGradient>
</defs>`;

async function readCrop(crop) {
  return sharp(sourcePath).extract({ left: crop[0], top: crop[1], width: crop[2], height: crop[3] }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
}

async function logoParts() {
  const { data, info } = await readCrop([65, 132, 248, 266]);
  const masks = Object.fromEntries(['fruit', 'leaf', 'ink', 'shine'].map(k => [k, new Uint8Array(info.width * info.height)]));
  for (let i = 0; i < masks.fruit.length; i++) {
    const [r, g, b] = data.subarray(i * info.channels, i * info.channels + 3);
    if (foreground(r, g, b)) {
      if (g < 110 && r < 64) masks.ink[i] = 1;
      else if (r < 125) masks.leaf[i] = 1;
      else masks.fruit[i] = 1;
    }
  }
  const solidFruit = fillHoles(masks.fruit, info.width, info.height);
  for (let i = 0; i < solidFruit.length; i++) {
    const [r, g, b] = data.subarray(i * info.channels, i * info.channels + 3);
    if (solidFruit[i] && r > 225 && g > 230 && b > 205) masks.shine[i] = 1;
  }
  const fruit = trace(solidFruit, info.width, info.height);
  const leaf = trace(fillHoles(masks.leaf, info.width, info.height), info.width, info.height);
  const ink = trace(masks.ink, info.width, info.height, 1.5, 0.32);
  const shine = trace(masks.shine, info.width, info.height, 1.8, 0.34);
  const color = shape(fruit, 'url(#fruit)') + shape(leaf, 'url(#leaf)') + shape(ink, palette.ink) + shape(shine, palette.background);
  // Eyes/dots and the shine are negative space in single-color exports.
  const silhouette = Uint8Array.from(solidFruit, (v, i) => (v || masks.leaf[i] || masks.ink[i]) ? 1 : 0);
  const silhouettePath = trace(silhouette, info.width, info.height);
  const cuts = trace(Uint8Array.from(masks.shine, (v, i) => (v || (solidFruit[i] && masks.ink[i])) ? 1 : 0), info.width, info.height, 1.5, 0.32);
  return { color, silhouettePath, cuts, bounds: [248, 266] };
}

async function wordmark() {
  const { data, info } = await readCrop([315, 197, 530, 203]);
  const mask = new Uint8Array(info.width * info.height);
  for (let i = 0; i < mask.length; i++) {
    const r = data[i * info.channels], g = data[i * info.channels + 1];
    mask[i] = r < 145 && g < 170 ? 1 : 0;
  }
  return trace(mask, info.width, info.height, 2, 0.4);
}

async function mascot(crop, name) {
  const { data, info } = await readCrop(crop);
  const width = info.width, height = info.height, count = width * height;
  const visible = new Uint8Array(count);
  const masks = Object.fromEntries(['leaf', 'vein', 'rind', 'ink', 'pith', 'yellow', 'water', 'glass'].map(k => [k, new Uint8Array(count)]));
  for (let i = 0; i < count; i++) {
    const [r, g, b] = data.subarray(i * info.channels, i * info.channels + 3);
    visible[i] = foreground(r, g, b) ? 1 : 0;
  }
  const silhouette = fillHoles(visible, width, height);
  for (let i = 0; i < count; i++) {
    if (!silhouette[i]) continue;
    const x = i % width, y = (i / width) | 0;
    const [r, g, b] = data.subarray(i * info.channels, i * info.channels + 3);
    if (r < 92 && g < 109 && b < 95) masks.ink[i] = 1;
    else if (b > r + 9 && g > r + 12 && b > g - 9) masks.water[i] = 1;
    else if (r > 188 && g > 160 && b < 175 && r > g + 14) masks.yellow[i] = 1;
    else if (r > 215 && g > 220 && b > 180) masks.pith[i] = 1;
    else if (r < 111 && g > r + 18) {
      if (y < height * 0.29) masks.leaf[i] = 1;
      else masks.rind[i] = 1;
    } else if (y < height * 0.25 && r > 147 && g > 171 && b < 166) masks.vein[i] = 1;
  }
  // White glass rim/bottom are open to the pale board and need an explicit silhouette.
  let glass = '';
  if (name === 'su-molasi') {
    glass = '<path fill="#F9FCF2" d="M48 127C46 120 59 117 72 117C85 117 96 120 95 126L90 172C89 178 81 180 71 180C61 180 53 177 53 173Z"/><path fill="#9BD3D4" d="M54 137Q72 143 89 137L85 171Q72 176 58 171Z"/><ellipse cx="71.5" cy="125" rx="19.5" ry="4" fill="#DDEBCF"/><path d="M55 132L59 166" fill="none" stroke="#F9FCF2" stroke-width="3" stroke-linecap="round"/>';
  }
  let body = shape(trace(silhouette, width, height, 2.5), 'url(#body)');
  body += shape(trace(masks.leaf, width, height), 'url(#leaf)');
  body += shape(trace(masks.vein, width, height, 1), '#A8CD82');
  body += shape(trace(masks.rind, width, height), 'url(#rind)');
  body += shape(trace(masks.pith, width, height, 8, 0.65), '#FFF9E6');
  body += shape(trace(masks.yellow, width, height, 1.6, 0.34), 'url(#yellow)');
  body += shape(trace(masks.water, width, height), '#99D1D5');
  body += shape(trace(masks.ink, width, height, 1, 0.3), palette.ink);
  body += glass;
  // The water pose's left hand crosses in front of its glass; trace it from the source.
  if (name === 'su-molasi') {
    const hand = new Uint8Array(count);
    for (let y = 135; y < 159; y++) for (let x = 35; x < 63; x++) {
      const i = y * width + x, r = data[i * info.channels], g = data[i * info.channels + 1], b = data[i * info.channels + 2];
      if (r > 105 && r < 170 && g > r + 25 && g - b > 37) hand[i] = 1;
    }
    body += shape(trace(hand, width, height, 1.5), 'url(#body)');
  }
  const bodyWidths = { merhaba: 348, 'goz-kirpma': 154, 'su-molasi': 154, kutlama: 158 };
  const scale = Math.min(880 / width, 880 / height, 600 / bodyWidths[name]);
  const tx = (1024 - width * scale) / 2, ty = 952 - height * scale;
  return `<g transform="translate(${n(tx)} ${n(ty)}) scale(${n(scale)})">${body}</g>`;
}

const assets = [];
async function saveAsset(relative, title, content, width, height) {
  const stem = path.join(root, relative);
  fs.mkdirSync(path.dirname(stem), { recursive: true });
  const svg = `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-labelledby="asset-title"><title id="asset-title">${escape(title)}</title><desc>Onaylı Limely marka görselinden vektörleştirilmiş sabit çizim. Şeffaf zemin; harici font veya gömülü raster içermez.</desc>${defs}${content}</svg>\n`;
  fs.writeFileSync(stem + '.svg', svg);
  const pngWidth = relative.includes('yazili') ? 2400 : 2048;
  await sharp(Buffer.from(svg)).resize({ width: pngWidth }).png().toFile(stem + '.png');
  const metadata = await sharp(stem + '.png').metadata();
  assets.push({ id: path.basename(relative), title, svg: relative.replaceAll('\\', '/') + '.svg', png: relative.replaceAll('\\', '/') + '.png', width: metadata.width, height: metadata.height });
}

async function main() {
  fs.mkdirSync(root, { recursive: true });
  const logo = await logoParts(), letters = await wordmark();
  for (const [variant, color] of [['renkli', null], ['koyu', palette.ink], ['beyaz', '#FFFFFF']]) {
    const symbol = color ? `<defs><mask id="symbol-cut" maskUnits="userSpaceOnUse" x="-4" y="-4" width="256" height="274">${shape(logo.silhouettePath, '#FFFFFF')}${shape(logo.cuts, '#000000')}</mask></defs><rect x="-3" y="-3" width="254" height="272" fill="${color}" mask="url(#symbol-cut)"/>` : logo.color;
    await saveAsset(`logolar/limely-simge-${variant}`, `Limely lime simgesi — ${variant}`, `<g transform="translate(82 52) scale(3.47)">${symbol}</g>`, 1024, 1024);
    await saveAsset(`logolar/limely-yazili-logo-${variant}`, `Limely yazılı logo — ${variant}`, `<g transform="translate(14 12)">${symbol}<g transform="translate(250 65)">${shape(letters, color || palette.ink)}</g></g>`, 808, 290);
  }
  for (const [name, crop, title] of [
    ['merhaba', [904, 26, 514, 443], 'Merhaba — el sallayan Limely'],
    ['goz-kirpma', [781, 503, 204, 215], 'Göz kırpan Limely'],
    ['su-molasi', [1007, 510, 207, 208], 'Su molası veren Limely'],
    ['kutlama', [1240, 505, 238, 213], 'Küçük kutlama yapan Limely'],
  ]) await saveAsset(`maskotlar/limely-maskot-${name}`, title, await mascot(crop, name), 1024, 1024);

  const sourceSha256 = crypto.createHash('sha256').update(fs.readFileSync(sourcePath)).digest('hex');
  const manifest = { package: 'Limely sabit marka varlıkları', version: '1.0.0', source: 'source/onayli-konsept.png', sourceSha256, method: 'Kaynak görselin konturları Bezier eğrilerine dönüştürüldü ve kenarlar yumuşatıldı; dolgu gradyanları düzenlendi. Su bardağının açık kenarı vektör konturla tamamlandı. PNG dosyaları SVG ana dosyalarından render edildi. Bu işlem raster kaynağın piksel kopyası değil, aynı kimliğin vektör uyarlamasıdır.', svg: 'Gerçek vektör: path, linearGradient ve tek renkli simgelerde mask; gömülü bitmap ve font yok.', sourcePreserved: true, background: 'transparent', palette, assets };
  fs.writeFileSync(path.join(root, 'asset-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  fs.writeFileSync(path.join(root, 'KULLANIM.txt'), `LIMELY — SABİT LOGO VE MASKOT PAKETİ v1\n\nBu paketin çizimleri onaylı limely-logo-maskot.png konseptinden vektörleştirildi.\nSVG ana dosyadır. PNG aynı SVG'den üretilmiştir ve şeffaf zeminlidir.\nSVG içinde bitmap, font, harici dosya veya JavaScript bulunmaz.\nKaynak konsept ve mevcut uygulama dosyaları değiştirilmedi.\n\nUĞUR İÇİN\n- Normal zemin: logolar/limely-yazili-logo-renkli.svg\n- Dar alan / favicon: logolar/limely-simge-renkli.svg\n- Koyu zemin: beyaz varyantlar\n- Tek renk baskı: koyu veya beyaz varyantlar\n- Ana maskot: maskotlar/limely-maskot-merhaba.svg\n- Diğer pozlar: goz-kirpma, su-molasi, kutlama\n- PNG karşılıkları SVG'lerle aynı adları taşır.\n- Şekilleri CSS ile yeniden çizme; dosyayı doğrudan img/Image olarak kullan.\n- En/boy oranını koru; renk filtresi, yatay esnetme veya otomatik yeniden üretim uygulama.\n\nÖRNEK REACT\n<img src="/brand/limely-yazili-logo-renkli.svg" alt="Limely" width={202} height={73} />\n<img src="/brand/limely-maskot-merhaba.svg" alt="El sallayan Limely" width={240} height={240} />\n\nDosya adları asset-manifest.json içindedir. PNG simge/maskot dosyaları 2048 px, yazılı logolar 2400 px genişliktedir.\nSVG ölçeklenebilir; büyük PNG'nin kaynakta bulunmayan yeni doku detayı eklediği iddia edilmez.\n`);
  console.log(JSON.stringify({ root, sourceSha256, assets: assets.length }, null, 2));
}
module.exports = { trace, shape, foreground, fillHoles, defs };
if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
