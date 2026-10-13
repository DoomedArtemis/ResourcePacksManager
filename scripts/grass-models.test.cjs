const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { png } = require('./moss-legacy-geometry.cjs');
const root = path.join(__dirname, '../resource_packs/better_grass');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const state = read('assets/minecraft/blockstates/grass_block.json');
assert.equal(state.multipart.length, 9);
const snowy = state.multipart.filter(part => part.when.snowy === 'true');
assert.equal(snowy.length, 1);
assert.deepEqual(snowy[0].apply, { model: 'minecraft:block/grass_block_snow' }, 'Snow keeps its vanilla model');
assert(state.multipart.every(part => ['true', 'false'].includes(part.when.snowy)), 'All details are gated by snow state');
const base = state.multipart.find(part => Array.isArray(part.apply) && part.apply[0].model === 'minecraft:block/grass_block');
assert.equal(base.apply.length, 4);
assert(base.apply.every(variant => variant.uvlock), 'Base uses vanilla dirt and biome-tinted grass');
for (const part of state.multipart) for (const variant of Array.isArray(part.apply) ? part.apply : [part.apply]) {
  if (!variant.model.startsWith('minecraft:block/better_grass/')) continue;
  const relative = variant.model.replace('minecraft:block/', 'assets/minecraft/models/block/') + '.json';
  assert(fs.existsSync(path.join(root, relative)), `Blockstate model exists: ${relative}`);
}
const directory = path.join(root, 'assets/minecraft/models/block/better_grass');
const topChoices = state.multipart[2].apply;
const totalWeight = topChoices.reduce((sum, choice) => sum + choice.weight, 0);
const surfacePebbleChance = topChoices.filter(choice => /\/pebbles?$/.test(choice.model)).reduce((sum, choice) => sum + choice.weight, 0) / totalWeight;
const dirt = read('assets/minecraft/blockstates/dirt.json');
assert.deepEqual(dirt.multipart[0].apply, { model: 'minecraft:block/dirt' }, 'Dirt keeps its vanilla base');
assert.equal(dirt.multipart.length, 6);
assert.deepEqual(dirt.multipart.slice(1), state.multipart.slice(4).map(({ apply }) => ({ apply })), 'Grass and dirt share sparse pebble placement');
for (const part of dirt.multipart.slice(1)) {
  const weight = part.apply.reduce((sum, choice) => sum + choice.weight, 0);
  const pebbleWeight = part.apply.filter(choice => !choice.model.endsWith('/none')).reduce((sum, choice) => sum + choice.weight, 0);
  assert(pebbleWeight / weight < surfacePebbleChance, 'Each buried face has fewer pebbles than the surface');
}
const flowerWeight = topChoices.filter(choice => /pink_petals|wildflowers|white_flowers|purple_flowers/.test(choice.model))
  .reduce((sum, choice) => sum + choice.weight, 0);
assert.equal(flowerWeight / totalWeight, 32 / 1632, 'Reduced flower frequency stays unchanged');
for (const name of ['stick', 'sticks', 'pebble', 'pebbles']) {
  const choices = topChoices.filter(choice => choice.model.endsWith(`/${name}`));
  assert.deepEqual(choices.map(choice => choice.y), [0, 90, 180, 270], 'Litter varies across four directions');
  const model = read(`assets/minecraft/models/block/better_grass/${name}.json`);
  for (const element of model.elements) {
    assert(element.from[1] > 16 && element.to[1] <= 18, 'Litter rests just above the grass');
    assert.equal(element.from[1], element.to[1], 'Litter uses flat pixel-art sprites rather than cuboids');
    assert(element.to[0] > element.from[0] && element.to[2] > element.from[2]);
    assert(Object.keys(element.faces).every(side => side === 'up' || side === 'down'), 'No voxel side faces');
  }
}
const images = new Map();
let faces = 0;
for (const file of fs.readdirSync(directory)) {
  const model = read(`assets/minecraft/models/block/better_grass/${file}`);
  assert(!model.parent, 'Decorations do not accidentally inherit a second full block');
  for (const element of model.elements) for (const [side, face] of Object.entries(element.faces)) {
    const texture = model.textures[face.texture.slice(1)];
    assert(texture.startsWith('minecraft:block/better_grass/'), 'All decoration textures are included in this pack');
    const relative = texture.replace('minecraft:', 'assets/minecraft/textures/') + '.png';
    assert(fs.existsSync(path.join(root, relative)));
    if (!images.has(relative)) images.set(relative, png(path.join(root, relative)));
    const image = images.get(relative);
    const axes = ['north', 'south'].includes(side) ? [0, 1] : ['east', 'west'].includes(side) ? [2, 1] : [0, 2];
    for (let i = 0; i < 2; i++) {
      assert(Math.abs(element.to[axes[i]] - element.from[axes[i]] - Math.abs(face.uv[i + 2] - face.uv[i])) < 0.01, `1:1 pixels: ${file}/${side}`);
    }
    if (element.rotation) assert.equal(element.rotation.rescale, false);
    for (let y = Math.floor(Math.min(face.uv[1], face.uv[3]) + 1e-8); y < Math.ceil(Math.max(face.uv[1], face.uv[3]) - 1e-8); y++) {
      for (let x = Math.floor(Math.min(face.uv[0], face.uv[2]) + 1e-8); x < Math.ceil(Math.max(face.uv[0], face.uv[2]) - 1e-8); x++) {
        assert(image.opacity(x, y) >= 128, `No transparent pixels on old solid blocks: ${file}`);
      }
    }
    if (['#clover', '#sprouts', '#stem', '#turf'].includes(face.texture)) assert.equal(face.tintindex, 0, 'Greenery follows biome grass tint');
    else assert.equal(face.tintindex, undefined, 'Flower colors stay untinted');
    if (file.startsWith('fringe')) {
      assert.equal(Math.abs(element.rotation.angle), 20);
      assert.equal(element.rotation.origin[1], 16, 'Turf hangs from the top edge');
      assert(element.from[1] >= 13 && element.to[1] <= 16, 'Dirt sides remain visible');
      assert.equal(face.cullface, element.name);
    } else if (file === 'pebble_side.json') {
      assert.equal(side, 'north');
      assert.equal(face.cullface, 'north', 'Side pebbles hide against neighboring blocks');
      assert(element.from[2] < 0 && element.to[2] < 0, 'Side pebbles clear the dirt face');
    } else if (file === 'pebble_bottom.json') {
      assert.equal(side, 'down');
      assert.equal(face.cullface, 'down', 'Bottom pebbles hide against neighboring blocks');
      assert(element.from[1] < 0 && element.to[1] < 0, 'Bottom pebbles clear the dirt face');
    } else assert.equal(face.cullface, 'up', 'Top details hide under solid blocks');
    faces++;
  }
}
const rules = read('variants/legacy-angle/manifest.json').FileVariants;
assert.equal(rules.length, 3);
for (const rule of rules) {
  assert.equal(rule.BeforeVersion, '1.21.6');
  const modern = read(rule.Path), legacy = read(rule.SourcePath);
  for (const element of modern.elements) element.rotation.angle = Math.sign(element.rotation.angle) * 22.5;
  assert.deepEqual(legacy, modern, 'Older versions use legal angles and identical geometry');
}
console.log(`Validated snowy behavior, self-contained textures, biome tint, opaque geometry, pixel scale, and legacy angles across ${faces} faces.`);
