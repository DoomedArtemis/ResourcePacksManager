const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { geometry, species, directions } = require('./update-bushy-leaves-enhanced.cjs');
const { adapt, scan } = require('./bushy-leaves-enhanced-compatibility.cjs');
const { accents, accentTypes, sprites, spritePixels, spritePng, detailModel, detailChoices } = require('./bushy-leaves-enhanced-details.cjs');
const root = path.resolve(__dirname, '../resource_packs/bushy_leaves_enhanced');
const read = relative => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
const modelPath = id => { const [ns, model] = id.split(':'); return `assets/${ns}/models/${model}.json`; };

for (const profile of new Set(Object.values(species).map(s => s[0]))) {
  const signatures = new Set();
  for (let layout = 0; layout < 3; layout++) for (const tinted of [true, false]) {
    const model = geometry(profile, layout, tinted);
    const stored = read(`assets/bushy_leaves_enhanced/models/block/${profile}_${layout}${tinted ? '' : '_untinted'}.json`);
    assert.deepEqual(stored, model);
    if (tinted) signatures.add(JSON.stringify(model.elements));
    let quads = 0;
    const fans = new Map();
    for (const [index, e] of model.elements.entries()) {
      let fan;
      if (index) {
        assert.equal(e.from.filter((n, i) => n === e.to[i]).length, 1, 'Only zero-thickness foliage planes beyond the core');
        assert.equal(Object.keys(e.faces).length, 2, 'Planes must be visible from both sides');
        assert.equal(new Set(Object.values(e.faces).map(f => f.cullface)).size, 1, 'Both sides cull with the supporting boundary');
        assert.ok([-45, -22.5, 22.5, 45].includes(e.rotation.angle));
        const key = JSON.stringify([e.rotation, Object.values(e.faces)[0].cullface]);
        if (!fans.has(key)) fans.set(key, { span: [Infinity, -Infinity], parts: [] });
        fan = fans.get(key);
        fan.parts.push(e);
      } else {
        assert.deepEqual(e.from, [0, 0, 0]); assert.deepEqual(e.to, [16, 16, 16]);
        assert.deepEqual(Object.keys(e.faces), directions);
      }
      for (const p of [e.from, e.to]) for (const v of p) assert.ok(v >= -4 && v <= 20, 'Restrained geometry bounds');
      // Bound actual rotated vertices, not just the unrotated element box.
      for (let bits = 0; bits < 8; bits++) {
        let p = e.from.map((v, i) => bits & (1 << i) ? e.to[i] : v);
        if (e.rotation) {
          const { axis, origin, angle } = e.rotation;
          const [a, b] = { x: [1, 2], y: [2, 0], z: [0, 1] }[axis];
          const c = Math.cos(angle * Math.PI / 180), s = Math.sin(angle * Math.PI / 180);
          const u = p[a] - origin[a], v = p[b] - origin[b];
          p[a] = origin[a] + u * c - v * s; p[b] = origin[b] + u * s + v * c;
        }
        assert.ok(p.every(v => v >= -6.5 && v <= 22.5), 'Keep the fuller foliage within controlled overhangs');
        if (index) {
          const normal = directions.indexOf(Object.values(e.faces)[0].cullface);
          const axis = normal < 2 ? 1 : normal < 4 ? 2 : 0;
          // Accumulate the actual span across the supporting block boundary.
          fan.span[0] = Math.min(fan.span[0], p[axis]);
          fan.span[1] = Math.max(fan.span[1], p[axis]);
        }
      }
      if (index) {
        assert.ok(e.rotation.origin.every(n => n >= 0 && n <= 16), 'All attachment centres are inside the core');
        const dimensions = e.from.map((n, i) => e.to[i] - n).filter(n => n > 0).sort((a, b) => a - b);
        const uv = Object.values(e.faces)[0].uv;
        assert.deepEqual([Math.abs(uv[2] - uv[0]), Math.abs(uv[3] - uv[1])].sort((a, b) => a - b), dimensions, 'Keep texture pixels at their native physical size');
      }
      for (const face of Object.values(e.faces)) {
        quads++;
        assert.equal(face.texture, '#all');
        assert.equal(face.tintindex, tinted ? 0 : undefined);
        assert.ok(directions.includes(face.cullface));
        assert.ok(face.uv.every(n => n >= 0 && n <= 16));
      }
    }
    assert.equal(fans.size, 12);
    for (const fan of fans.values()) {
      const [body, tip] = fan.parts;
      assert.equal(fan.parts.length, 2, 'One continuous root and one tapered tip');
      const direction = Object.values(body.faces)[0].cullface;
      const boundary = directions.indexOf(direction) % 2 ? 16 : 0;
      assert.ok(fan.span[0] < boundary && fan.span[1] > boundary, 'Every fan is rooted across its supporting face');
      const projection = boundary === 16 ? fan.span[1] - boundary : boundary - fan.span[0];
      assert.ok(projection >= 3.5 && projection <= 6.5, 'Preserve the bushy silhouette instead of shrinking fans back against the cube');
      const joinFrom = body.from.map((n, i) => Math.max(n, tip.from[i]));
      const joinTo = body.to.map((n, i) => Math.min(n, tip.to[i]));
      assert.ok(joinFrom.every((n, i) => n <= joinTo[i]), 'Tip and body must touch');
      assert.equal(joinFrom.filter((n, i) => n < joinTo[i]).length, 1, 'Parts share an edge, with no overlapping surface');
      const point = joinFrom.map((n, i) => (n + joinTo[i]) / 2);
      const sample = e => {
        const [side, f] = Object.entries(e.faces)[0];
        const normal = side === 'up' ? 1 : side === 'north' ? 2 : 0;
        const [u, v] = normal === 1 ? [0, 2] : normal === 2 ? [0, 1] : [2, 1];
        const s = normal === 2 ? (e.to[u] - point[u]) / (e.to[u] - e.from[u]) : (point[u] - e.from[u]) / (e.to[u] - e.from[u]);
        const t = normal === 1 ? (point[v] - e.from[v]) / (e.to[v] - e.from[v]) : (e.to[v] - point[v]) / (e.to[v] - e.from[v]);
        return [f.uv[0] + s * (f.uv[2] - f.uv[0]), f.uv[1] + t * (f.uv[3] - f.uv[1])];
      };
      assert.ok(sample(body).every((n, i) => Math.abs(n - sample(tip)[i]) < 1e-8), 'Texture is continuous across the tapered tip');
    }
    assert.equal(quads, 54, 'Keep the quad budget bounded');
  }
  assert.equal(signatures.size, 3, 'All three silhouettes differ');
}
const rules = read('variants/leaves-versions.json').FileRules;
for (const [name, [, , minimum]] of Object.entries(species)) {
  const statePath = `assets/minecraft/blockstates/${name}_leaves.json`;
  const state = read(statePath);
  const variants = accents[name] ? state.multipart[0].apply : state.variants[''];
  assert.equal(variants.length, 12);
  assert.equal(new Set(variants.map(v => v.model + ':' + v.y)).size, 12);
  for (const variant of variants) {
    const wrapper = read(modelPath(variant.model));
    const template = read(modelPath(wrapper.parent));
    assert.equal(wrapper.textures.all, `minecraft:block/${name}_leaves`);
    assert.ok(template.elements);
    assert.equal(rules.find(r => r.Path === modelPath(variant.model))?.MinVersion, minimum);
  }
  assert.equal(rules.find(r => r.Path === statePath)?.MinVersion, minimum);
  const inventoryBlock = read(`assets/minecraft/models/block/${name}_leaves.json`);
  assert.equal(inventoryBlock.parent, `minecraft:block/bushy_leaves_enhanced/${name}_0`, 'Leaf items inherit the bushy species model');
  if (accents[name]) {
    assert.equal(state.multipart.length, 2);
    const choices = state.multipart[1].apply;
    assert.deepEqual(choices, detailChoices(name));
    const total = choices.reduce((n, c) => n + c.weight, 0);
    const decorated = choices.filter(c => !c.model.endsWith('/none')).reduce((n, c) => n + c.weight, 0);
    const types = accentTypes(name);
    const expected = types.reduce((n, type) => n + 1 / type.rarity, 0);
    assert.ok(Math.abs(decorated / total - expected) < 1e-12, 'Details must remain rare');
    for (const type of types) {
      const weight = choices.filter(c => type.placements.some(p => c.model === `bushy_leaves_enhanced:block/details/${type.modelPrefix}_${p}`)).reduce((n, c) => n + c.weight, 0);
      assert.equal(weight / total, 1 / type.rarity, 'Preserve the frequency of each distinct accent');
    }
    assert.equal(new Set(choices.slice(1).map(c => c.model + ':' + c.y)).size, types.reduce((n, type) => n + type.placements.length * 4, 0));
    for (const choice of choices) assert.ok(fs.existsSync(path.join(root, modelPath(choice.model))));
  }
}
assert.equal(Object.keys(accents).length, 7, 'Keep accents limited to selected leaf species');
for (const color of ['orange', 'yellow', 'red']) {
  const name = `${color}_poplar`;
  assert.ok(!accents[name], 'Poplar leaves have no special decorations');
  assert.equal(species[name][2], '26.3');
}
assert.equal(accentTypes('cherry').find(t => t.sprite === 'cherries').rarity, 18);
assert.equal(accentTypes('oak').find(t => t.sprite === 'oak_acorns').rarity, 18, 'Oak retains its acorns');
assert.ok(['oak', 'dark_oak'].every(name => accentTypes(name).some(t => t.sprite === 'apple')), 'Both oak species have apples');
assert.equal(accentTypes('oak').find(t => t.sprite === 'oak_blossoms').rarity, 18);
assert.equal(accentTypes('dark_oak').find(t => t.sprite === 'oak_blossoms').rarity, 32);
assert.equal(accentTypes('spruce').find(t => t.sprite === 'spruce_growth').rarity, 12);
for (const name of ['spruce']) {
  assert.ok(accentTypes(name).every(type => !type.placements.includes('top')), 'No ornaments grow on top of spruce');
  assert.ok(detailChoices(name).every(choice => !choice.model.endsWith('_top')));
  for (const type of accentTypes(name)) assert.ok(!fs.existsSync(path.join(root, `assets/bushy_leaves_enhanced/models/block/details/${type.modelPrefix}_top.json`)), 'Remove stale top models from packaged sources');
}
assert.ok(['jungle_vine_short', 'jungle_vine_long'].every(sprite => accentTypes('jungle').some(t => t.sprite === sprite)));
assert.ok(!accents.azalea, 'Only flowering azalea gets projecting blossoms');
assert.deepEqual(read('assets/bushy_leaves_enhanced/models/block/details/none.json').elements, [], 'Most blocks add no decoration quads');
for (const name of Object.keys(sprites)) {
  const pixels = spritePixels(name).pixels;
  const png = spritePng(name);
  assert.deepEqual(fs.readFileSync(path.join(root, `assets/bushy_leaves_enhanced/textures/block/details/${name}.png`)), png);
  assert.equal(png.readUInt32BE(16), 16);
  assert.equal(png.readUInt32BE(20), 16);
  let painted = 0;
  for (let i = 3; i < pixels.length; i += 4) {
    assert.ok(pixels[i] === 0 || pixels[i] === 255, 'Use clean cutout pixels, without translucent halos');
    if (pixels[i]) painted++;
  }
  assert.ok(painted > 8 && painted < 40, 'Coarse, readable ornaments rather than miniaturized high-resolution icons');
  if (sprites[name].surface) {
    assert.ok(painted <= 12, 'Blossoms cover less than five percent of one face, leaving the foliage dominant');
    continue;
  }
  const connected = new Set(), queue = [];
  const first = pixels.findIndex((n, i) => i % 4 === 3 && n > 0);
  queue.push((first - 3) / 4);
  while (queue.length) {
    const p = queue.pop();
    if (connected.has(p)) continue;
    connected.add(p);
    for (const [dx, dy] of [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]) {
      const x = p % 16 + dx, y = Math.floor(p / 16) + dy;
      if (x >= 0 && x < 16 && y >= 0 && y < 16 && pixels[(y * 16 + x) * 4 + 3] && !connected.has(y * 16 + x)) queue.push(y * 16 + x);
    }
  }
  assert.equal(connected.size, painted, 'All ornament pixels attach to their stem');
}
for (const name of Object.keys(accents)) for (const type of accentTypes(name)) for (const placement of type.placements) {
  const model = read(`assets/bushy_leaves_enhanced/models/block/details/${type.modelPrefix}_${placement}.json`);
  assert.equal(rules.find(r => r.Path === `assets/bushy_leaves_enhanced/models/block/details/${type.modelPrefix}_${placement}.json`)?.MinVersion, species[name][2], 'Gate species accents to the same Minecraft versions as their leaves');
  assert.deepEqual(model, detailModel(name, placement, type.sprite));
  assert.equal(model.textures.particle, `minecraft:block/${name}_leaves`, 'Leaf particles remain leaf particles');
  let quads = 0;
  for (const element of model.elements) {
    assert.equal(element.from.filter((n, i) => n === element.to[i]).length, 1, 'Ornaments use flat planes, never cubes');
    const minimum = sprites[type.sprite].trailing ? -12 : -8;
    const maximum = sprites[type.sprite].growth ? 22.5 : 16.03;
    for (const point of [element.from, element.to]) assert.ok(point.every(n => n >= minimum && n <= maximum), 'Small ornaments stay close to the leaf');
    for (const face of Object.values(element.faces)) {
      quads++;
      assert.equal(face.tintindex, sprites[type.sprite].tinted ? 0 : undefined, 'Tint vegetative growth with the leaves; keep fruits and flowers untinted');
      assert.equal(face.cullface, placement === 'side' ? 'north' : placement === 'top' ? 'up' : 'down', 'Hide accents against an occluding neighbour');
      const dimensions = element.from.map((n, i) => element.to[i] - n).filter(n => n > 0).sort((a, b) => a - b);
      const spans = [Math.abs(face.uv[2] - face.uv[0]), Math.abs(face.uv[3] - face.uv[1])].sort((a, b) => a - b);
      assert.deepEqual(spans, dimensions, 'Every ornament pixel is exactly one model unit, matching vanilla 16x16 textures');
    }
  }
  assert.equal(quads, sprites[type.sprite].surface ? 2 : 4, 'Keep accents inexpensive and flowers confined to one face');
}
assert.deepEqual(read('assets/minecraft/models/block/leaves.json'), geometry());
assert.ok(!fs.existsSync(path.join(root, 'assets/minecraft/models/item')), 'Do not supply leaf item model overrides');
assert.ok(!fs.existsSync(path.join(root, 'assets/minecraft/items')), 'Do not supply leaf item definition overrides');
assert.ok(!fs.existsSync(path.join(root, 'assets/minecraft/models/block/cube_all.json')), 'Never change non-leaf cubes');

const models = {
  'test:block/automatic': { parent: 'minecraft:block/leaves', textures: { all: 'test:block/green' } },
  'test:block/cube': { parent: 'minecraft:block/cube_all', textures: { all: 'test:block/pink' } },
  'test:block/child': { parent: 'test:block/cube', textures: { all: '#foliage', foliage: 'test:block/animated' } },
  'test:block/tinted': { ...geometry(), elements: [geometry().elements[0]], textures: { all: 'test:block/tinted' } },
  'test:block/fruit': { parent: 'minecraft:block/leaves', elements: [{ from: [4, 4, 4], to: [12, 12, 12], faces: {} }] },
  'test:block/custom': { parent: 'minecraft:block/leaves', loader: 'test:dynamic' },
  'test:block/cycle': { parent: 'test:block/cycle' },
  'test:block/alias_cycle': { parent: 'minecraft:block/cube_all', textures: { all: '#a', a: '#all' } },
  'test:block/empty': { parent: 'minecraft:block/leaves', elements: [] },
  'test:block/missing': { parent: 'test:block/absent' },
  'test:block/stone_child': { parent: 'test:block/tinted' },
};
assert.equal(adapt(models, 'test:block/automatic').status, 'automatic');
assert.match(adapt(models, 'test:block/cube').model.parent, /_untinted$/);
assert.equal(adapt(models, 'test:block/child').model.textures.all, 'test:block/animated');
assert.equal(adapt(models, 'test:block/tinted').model.parent, 'bushy_leaves_enhanced:block/broad_0');
for (const name of ['fruit', 'custom', 'cycle', 'alias_cycle', 'empty', 'missing']) assert.equal(adapt(models, `test:block/${name}`).status, 'skipped', name);
const state = model => ({ variants: { '': { model } } });
const result = scan({ models, tags: {
  'minecraft:leaves': { values: ['#test:foliage'] }, 'test:foliage': { values: [{ id: 'test:canopy', required: false }, '#minecraft:leaves'] },
}, blockstates: {
  'test:pink_leaves': state('test:block/cube'), 'test:canopy': state('test:block/child'),
  'test:green_leaves': state('test:block/automatic'), 'test:stone': state('test:block/stone_child'),
  'test:tinted_leaves': state('test:block/tinted'),
  'test:fruit_leaves': { multipart: [{ apply: { model: 'test:block/fruit' } }] },
} });
assert.deepEqual(Object.keys(result.overrides).sort(), ['test:block/child', 'test:block/cube']);
assert.equal(result.report.find(r => r.model === 'test:block/tinted').status, 'skipped');
console.log('Passed flat geometry, rotated bounds, culling, tint, UVs, quad budget, species variation and version rules.');
console.log('Passed rare species accents, oak/dark oak apples, individual frequencies, flat placements, native pixel scale and weighted empty overlays.');
console.log('Passed inheritance, texture aliasing, nested leaf tags, tint preservation, cycles and conservative compatibility skips.');
