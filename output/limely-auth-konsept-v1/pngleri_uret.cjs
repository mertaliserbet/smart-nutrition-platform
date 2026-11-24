const fs = require('node:fs');
const path = require('node:path');
const packageDirectory = process.argv[2];
if (!packageDirectory) throw new Error('Bundled Node package directory is required.');
const sharp = require(require.resolve('sharp', { paths: [packageDirectory] }));

(async () => {
  for (const name of fs.readdirSync(__dirname).filter(name => name.endsWith('.svg'))) {
    const input = path.join(__dirname, name);
    const scale = name.startsWith('limely-') ? 1.5 : 3;
    await sharp(input, {density: 72 * scale}).png().toFile(input.replace(/\.svg$/, '.png'));
  }
  console.log('3 screen PNGs and the comparison board rendered.');
})().catch(error => { console.error(error); process.exitCode = 1; });
