const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { combine } = require('./update-combined-bushy-leaves-enhanced.cjs');
const root = path.resolve(__dirname, '..');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
const components = {};
for (const pack of ['bushy_leaves_enhanced', 'alternative_birch_leaves', 'flowering_oak_leaves']) {
  components[pack] = {};
  const source = path.join(root, 'resource_packs', pack);
  for (const name of fs.readdirSync(source, { recursive: true })) {
    if (name.startsWith('assets' + path.sep) && name.endsWith('.json')) {
      components[pack][name.replaceAll(path.sep, '/')] = read(`resource_packs/${pack}/${name}`);
    }
  }
}
const before = JSON.stringify(components);
const result = combine(components);
assert.equal(JSON.stringify(components), before, 'Keep individual source packs unchanged');
assert.deepEqual(combine({}), {});
assert.deepEqual(combine({ bushy_leaves_enhanced: components.bushy_leaves_enhanced }), {});
assert.deepEqual(Object.keys(combine({ bushy_leaves_enhanced: components.bushy_leaves_enhanced,
  flowering_oak_leaves: components.flowering_oak_leaves })), ['flowering_oak_leaves']);
for (const [pack, assets] of Object.entries(result)) {
  for (const [name, document] of Object.entries(assets)) {
    assert.deepEqual(read(`artemis_enhanced_visuals/compatibility/bushy_leaves_enhanced+${pack}/${name}`), document);
  }
}
const birch = result.alternative_birch_leaves;
const birchState = birch['assets/minecraft/blockstates/birch_leaves.json'];
assert.equal(birch['assets/minecraft/models/block/birch_leaves.json'].parent, 'bushy_leaves_enhanced:block/combined/birch_0');
assert.equal(birchState.multipart[0].apply.length, 12);
assert.deepEqual(birchState.multipart[1], components.bushy_leaves_enhanced['assets/minecraft/blockstates/birch_leaves.json'].multipart[1]);
for (let layout = 0; layout < 3; layout++) {
  const wrapper = birch[`assets/bushy_leaves_enhanced/models/block/combined/birch_${layout}.json`];
  assert.equal(wrapper.textures.all, 'minecraft:block/birch_leaves');
  const template = components.bushy_leaves_enhanced[`assets/bushy_leaves_enhanced/models/block/airy_${layout}_untinted.json`];
  assert.equal(wrapper.parent, `bushy_leaves_enhanced:block/airy_${layout}_untinted`);
  assert.ok(template.elements.length > 1);
  assert.ok(template.elements.every(e => Object.values(e.faces).every(f => f.tintindex === undefined)));
}
const oak = result.flowering_oak_leaves;
const state = oak['assets/minecraft/blockstates/oak_leaves.json'];
assert.equal(oak['assets/minecraft/models/item/oak_leaves.json'].parent, 'bushy_leaves_enhanced:block/combined/flowering_oak_leaves_1_0');
for (const part of state.multipart.filter(p => p.when)) {
  const original = components.flowering_oak_leaves['assets/minecraft/blockstates/oak_leaves.json'].variants[`persistent=${part.when.persistent}`];
  const total = part.apply.reduce((sum, v) => sum + v.weight, 0);
  const flowers = part.apply.filter(v => v.model.includes('/combined/')).reduce((sum, v) => sum + v.weight, 0);
  assert.equal(flowers / total, part.when.persistent === 'true' ? 0.1 : 0.05);
  for (const choice of original) {
    const name = choice.model.split('/').pop();
    const selected = part.apply.filter(v => choice.model === 'minecraft:block/oak_leaves'
      ? v.model.startsWith('minecraft:block/bushy_leaves_enhanced/oak_') : v.model.includes(`/combined/${name}_`));
    assert.equal(selected.length, 12, 'Every flower choice retains all foliage layouts and rotations');
    const probability = selected.reduce((sum, v) => sum + v.weight, 0) / total;
    assert.equal(probability, choice.weight / original.reduce((sum, v) => sum + v.weight, 0));
  }
}
for (const [name, model] of Object.entries(oak).filter(([name]) => name.includes('/models/block/combined/'))) {
  const layout = Number(name.match(/_(\d)\.json$/)[1]);
  const base = components.bushy_leaves_enhanced[`assets/bushy_leaves_enhanced/models/block/broad_${layout}.json`];
  assert.equal(model.elements.length, base.elements.length * 2);
  assert.deepEqual(model.elements.slice(0, base.elements.length), base.elements);
  assert.ok(model.elements.slice(base.elements.length).every(e => Object.values(e.faces).every(f => f.texture === '#flowers' && f.tintindex === undefined)));
  assert.ok(model.textures.flowers.startsWith('minecraft:block/oak_flowers_'));
}
console.log('Passed combined leaf assets, optional components, bushy geometry, golden birch tint, oak flower probabilities and untinted flower overlays.');
