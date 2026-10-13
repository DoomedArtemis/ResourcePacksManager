const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.join(__dirname, '../resource_packs/better_candles');
const source = path.join(__dirname, '../resource_packs/better_candles/assets/minecraft/models/block');
const templates = ['template_candle', 'template_two_candles', 'template_three_candles', 'template_four_candles'];
const names = ['one_candle', 'two_candles', 'three_candles', 'four_candles'];
for (const name of templates) assert(fs.existsSync(path.join(source, `${name}.json`)), 'Use existing Better Candles geometry');
const models = path.join(root, 'assets/dye_depot/models/block');
const files = fs.readdirSync(models);
assert.equal(files.length, 256);
const colors = new Set();
for (const file of files) {
  const match = file.match(/^(.+)_candle_(one_candle|two_candles|three_candles|four_candles|[1-4])(_lit)?\.json$/);
  assert(match, `Recognized upstream model name: ${file}`);
  const [, color, count, lit = ''] = match;
  colors.add(color);
  const index = names.includes(count) ? names.indexOf(count) : Number(count) - 1;
  const model = JSON.parse(fs.readFileSync(path.join(models, file), 'utf8'));
  assert.equal(model.parent, `minecraft:block/${templates[index]}`);
  assert.equal(model.textures.candle, `dye_depot:block/${color}_candle${lit}`);
  assert.equal(model.textures.particle, model.textures.candle);
  assert.equal(model.textures.all, model.textures.candle);
  const floorName = `${color}_candle_floor${index === 0 ? '' : `_${index + 1}`}`;
  assert.equal(model.textures.floor, `dye_depot:block/${floorName}`);
  assert(fs.existsSync(path.join(root, `assets/dye_depot/textures/block/${floorName}.png`)));
  const template = JSON.parse(fs.readFileSync(path.join(source, `${templates[index]}.json`), 'utf8'));
  for (const element of template.elements) for (const face of Object.values(element.faces)) {
    assert(model.textures[face.texture.slice(1)], `Resolved template texture variable: ${face.texture}`);
  }
}
assert.equal(colors.size, 16);
console.log('Validated all 16 colors, four counts, lit/unlit states, both naming schemes, and shared geometry.');
