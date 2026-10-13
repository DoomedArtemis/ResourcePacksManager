const fs = require('node:fs');
const path = require('node:path');
const { parse, format } = require('./format-json.cjs');
const root = path.join(__dirname, '../resource_packs/better_candles');
const colors = ['amber', 'aqua', 'beige', 'coral', 'forest', 'ginger', 'indigo', 'maroon', 'mint', 'navy', 'olive', 'rose', 'slate', 'tan', 'teal', 'verdant'];
const counts = ['one_candle', 'two_candles', 'three_candles', 'four_candles'];
const templates = ['template_candle', 'template_two_candles', 'template_three_candles', 'template_four_candles'];
for (const color of colors) {
  const floor = `dye_depot:block/${color}_candle_floor`;
  if (!fs.existsSync(path.join(root, `assets/dye_depot/textures/block/${color}_candle_floor.png`))) {
    throw new Error(`Missing supplied floor texture: ${color}`);
  }
  for (const [index, count] of counts.entries()) for (const lit of ['', '_lit']) {
    const candle = `dye_depot:block/${color}_candle${lit}`;
    const clusterFloor = index === 0 ? floor : `${floor}_${index + 1}`;
    const model = { parent: `minecraft:block/${templates[index]}`, textures: {
      candle, floor: clusterFloor, particle: candle,
      // Dye Depot's original models use #all; retain it for inherited consumers.
      all: candle
    } };
    // Maintained 1.20/1.21 branches use numeric names. Legacy Forge and 26.1
    // use the vanilla-style names. Shipping both avoids mod-release assumptions.
    for (const suffix of [count, String(index + 1)]) {
      const file = path.join(root, `assets/dye_depot/models/block/${color}_candle_${suffix}${lit}.json`);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, format(parse(JSON.stringify(model))) + '\n');
    }
  }
}
console.log('Generated 256 Dye Depot candle models using the four exact Better Candles templates.');
