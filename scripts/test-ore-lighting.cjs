const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../resource_packs/alternative_ores');
const read = relative => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
const routing = read('variants/ore-versions.json');
// Silent Gear references the shared deepslate helper before vanilla adds deepslate.
const deepslateHelper = routing.FileRules.find(rule => rule.Path === 'assets/minecraft/models/block/alternative_ores/legacy_lighting/deepslate.json');
assert.equal(deepslateHelper.MinVersion, '1.16.3', 'Silent Gear legacy blockstates need their deepslate helper starting in 1.16.3.');
const variants = routing.FileVariants.filter(rule => rule.SourcePath.startsWith('variants/legacy-lighting/'));
let expectedVariants = 0;
for (const namespace of fs.readdirSync(path.join(root,'assets'))) {
  const states = path.join(root,'assets',namespace,'blockstates');
  if (fs.existsSync(states)) expectedVariants += fs.readdirSync(states).filter(name=>name.endsWith('.json')).length;
  const layouts = path.join(root,'assets',namespace,'models/block/alternative_ores');
  if (fs.existsSync(layouts)) expectedVariants += fs.readdirSync(layouts).filter(name=>/^(?:copper_)?crystal_layout_[1-6]_overlay\.json$/.test(name)).length;
}
assert.equal(variants.length, expectedVariants);
const baseParents = new Map();
for (const variant of variants) {
  assert.equal(variant.BeforeVersion, '1.21.2');
  const original = read(variant.Path);
  const legacy = read(variant.SourcePath);
  if (variant.Path.includes('/blockstates/')) {
    const parent = original.multipart[0].apply.model;
    const legacyModel = legacy.multipart[0].apply.model;
    assert.match(legacyModel, /^[a-z0-9_.-]+:block\/alternative_ores\/legacy_lighting\//);
    const base = read('assets/' + legacyModel.replace(':', '/models/') + '.json');
    baseParents.set(legacyModel, parent);
    assert.equal(base.ambientocclusion, false);
    assert.equal(base.parent, undefined, 'Older clients ignore child AO overrides when a parent exists.');
    assert.deepEqual(base.elements.map(element => [element.from, element.to]), [[[0, 0, 0], [16, 16, 16]]]);
    const expected = {
      'minecraft:block/stone': { all: 'minecraft:block/stone' },
      'minecraft:block/netherrack': { all: 'minecraft:block/netherrack' },
      'minecraft:block/end_stone': { all: 'minecraft:block/end_stone' },
      'alltheores:block/alternative_ores/otherstone': { all: 'alltheores:block/alternative_ores/otherstone' },
      'minecraft:block/deepslate': { end: 'minecraft:block/deepslate_top', side: 'minecraft:block/deepslate' },
      'minecraft:block/alternative_ores/ancient_debris_base': { end: 'minecraft:block/ancient_debris_top', side: 'minecraft:block/ancient_debris_side' }
    }[parent] || read('assets/' + parent.replace(':', '/models/') + '.json').textures;
    for (const direction of ['down', 'up', 'north', 'south', 'west', 'east']) {
      const face = base.elements[0].faces[direction];
      const expectedTexture = expected.all || (direction === 'down' || direction === 'up' ? expected.end : expected.side);
      assert.equal(base.textures[face.texture.slice(1)], expectedTexture);
      assert.deepEqual(face, { texture: expected.all ? '#all' : (direction === 'down' || direction === 'up' ? '#end' : '#side'), cullface: direction });
    }
    legacy.multipart[0].apply.model = parent;
  } else {
    assert.equal(legacy.ambientocclusion, false);
    assert.equal(legacy.parent, undefined, 'Overlay must not inherit AO from block/block on older clients.');
    legacy.parent = original.parent;
    legacy.ambientocclusion = original.ambientocclusion;
  }
  // All vertices, UVs, texture references, rotations, cullfaces, weights, shade
  // flags, emission values and every unrelated JSON field must remain identical.
  assert.deepEqual(legacy, original, `Non-lighting change in ${variant.SourcePath}`);
}
// Independently compare the new parentless cubes with the effective geometry and
// textures in cached official Minecraft models for every legacy release available.
const matrix = fs.readFileSync(path.resolve(__dirname, '../config/minecraft-release-version-matrix.psd1'), 'utf8');
const versions = [...matrix.matchAll(/\bId\s*=\s*'([^']+)'/g)].map(match => match[1]);
let comparedVersions = 0;
for (const version of versions.slice(0, versions.indexOf('1.21.2'))) {
  const cache = path.resolve(__dirname, `../cache/vanilla-asset-catalogs/dependency-data/${version}.json`);
  if (!fs.existsSync(cache)) continue;
  const vanilla = JSON.parse(fs.readFileSync(cache, 'utf8').replace(/^\uFEFF/, '')).JsonAssets;
  const location = id => 'assets/' + (id.includes(':') ? id : 'minecraft:' + id).replace(':', '/models/') + '.json';
  function resolve(id) {
    const relative = location(id);
    const source = path.join(root, relative);
    const own = fs.existsSync(source) ? read(relative) : (vanilla[relative] ? JSON.parse(vanilla[relative]) : null);
    if (!own) return null;
    const parent = own.parent ? resolve(own.parent) : {};
    assert.ok(parent, `Missing parent in official ${version} model: ${own.parent}`);
    return { ...parent, ...own, textures: { ...parent.textures, ...own.textures } };
  }
  function appearance(model) {
    function texture(id, seen = new Set()) {
      if (id.startsWith('#')) {
        assert.ok(!seen.has(id), 'Texture reference cycle');
        seen.add(id);
        return texture(model.textures[id.slice(1)], seen);
      }
      return id.includes(':') ? id : 'minecraft:' + id;
    }
    const elements = structuredClone(model.elements);
    for (const element of elements) for (const face of Object.values(element.faces)) face.texture = texture(face.texture);
    return { elements, particle: texture(model.textures.particle) };
  }
  for (const [legacyId, parentId] of baseParents) {
    // These cores do not exist before their first vanilla release.
    if (parentId.includes('deepslate') && versions.indexOf(version) < versions.indexOf('1.17')) continue;
    if (parentId.includes('ancient_debris') && versions.indexOf(version) < versions.indexOf('1.16')) continue;
    const parent = resolve(parentId);
    assert.ok(parent, `Missing official model ${parentId} for ${version}`);
    assert.deepEqual(appearance(resolve(legacyId)), appearance(parent), `Cube shape, UVs or textures changed for ${parentId} in ${version}`);
  }
  comparedVersions++;
}
console.log(`Parentless rock geometry and resolved textures match official models across ${comparedVersions} cached legacy Minecraft releases.`);
const baselineArgument = process.argv.indexOf('--baseline');
if (baselineArgument !== -1) {
  const baselinePath = path.resolve(process.argv[baselineArgument + 1]);
  const baseline = JSON.parse(fs.readFileSync(baselinePath));
  for (const [relative, hash] of Object.entries(baseline)) {
    const current = crypto.createHash('sha256').update(fs.readFileSync(path.resolve(__dirname, '..', relative))).digest('hex');
    assert.equal(current, hash, `Existing source asset changed: ${relative}`);
  }
  console.log(`All ${Object.keys(baseline).length} original source assets remain byte-identical.`);
}
console.log(`Passed all ${variants.length} legacy lighting variants: textures, shapes, UVs, rotations, culling, and modern source models are preserved.`);
