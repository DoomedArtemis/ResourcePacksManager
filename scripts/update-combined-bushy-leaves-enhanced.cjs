const fs = require('node:fs');
const path = require('node:path');
const clone = value => structuredClone(value);
const modelPath = id => {
  const [namespace, name] = (id.includes(':') ? id : `minecraft:${id}`).split(':');
  return `assets/${namespace}/models/${name}.json`;
};

function combine(components) {
  const tree = components.bushy_leaves_enhanced;
  const output = {};
  if (!tree) return output;
  for (const [pack, species] of [['alternative_birch_leaves', 'birch'], ['flowering_oak_leaves', 'oak']]) {
    const component = components[pack];
    if (!component) continue;
    const statePath = `assets/minecraft/blockstates/${species}_leaves.json`;
    if (!tree[statePath]) continue;
    const state = clone(tree[statePath]);
    const foliage = state.multipart[0].apply;
    const assets = output[pack] = {};
    if (species === 'birch') {
      for (let layout = 0; layout < 3; layout++) {
        const original = `minecraft:block/bushy_leaves_enhanced/birch_${layout}`;
        const wrapper = clone(tree[modelPath(original)]);
        wrapper.parent += '_untinted';
        const replacement = `bushy_leaves_enhanced:block/combined/birch_${layout}`;
        assets[modelPath(replacement)] = wrapper;
        for (const variant of foliage) if (variant.model === original) variant.model = replacement;
      }
      assets['assets/minecraft/models/block/birch_leaves.json'] = { parent: 'bushy_leaves_enhanced:block/combined/birch_0' };
    } else {
      const parts = [];
      for (const [condition, choices] of Object.entries(component[statePath].variants)) {
        const apply = [];
        for (const choice of choices) for (const variant of foliage) {
          let model = variant.model;
          if (choice.model !== 'minecraft:block/oak_leaves') {
            const layout = Number(variant.model.match(/_(\d)$/)[1]);
            model = `bushy_leaves_enhanced:block/combined/${choice.model.split('/').pop()}_${layout}`;
            if (!assets[modelPath(model)]) {
              const wrapper = tree[modelPath(variant.model)];
              const geometry = clone(tree[modelPath(wrapper.parent)]);
              geometry.textures = { ...geometry.textures, ...wrapper.textures,
                flowers: component[modelPath(choice.model)].textures.flowers };
              const overlays = clone(geometry.elements);
              for (const element of overlays) {
                for (let axis = 0; axis < 3; axis++) {
                  if (element.from[axis] === element.to[axis]) {
                    const shift = element.from[axis] < 8 ? -0.01 : 0.01;
                    element.from[axis] += shift;
                    element.to[axis] += shift;
                  } else {
                    element.from[axis] -= 0.01;
                    element.to[axis] += 0.01;
                  }
                }
                for (const face of Object.values(element.faces)) {
                  face.texture = '#flowers';
                  delete face.tintindex;
                }
              }
              geometry.elements.push(...overlays);
              assets[modelPath(model)] = geometry;
            }
          }
          apply.push({ ...variant, model, weight: (choice.weight || 1) * variant.weight });
        }
        parts.push({ when: Object.fromEntries(condition.split(',').map(pair => pair.split('='))), apply });
      }
      state.multipart = [...parts, ...state.multipart.slice(1)];
      assets['assets/minecraft/models/item/oak_leaves.json'] = { parent: 'bushy_leaves_enhanced:block/combined/flowering_oak_leaves_1_0' };
    }
    assets[statePath] = state;
  }
  return output;
}

if (require.main === module) {
  const root = path.resolve(__dirname, '..');
  const components = {};
  for (const pack of ['bushy_leaves_enhanced', 'alternative_birch_leaves', 'flowering_oak_leaves']) {
    const source = path.join(root, 'resource_packs', pack);
    components[pack] = {};
    for (const name of fs.readdirSync(source, { recursive: true })) {
      if (name.startsWith('assets' + path.sep) && name.endsWith('.json')) {
        components[pack][name.replaceAll(path.sep, '/')] = JSON.parse(fs.readFileSync(path.join(source, name), 'utf8'));
      }
    }
  }
  for (const [pack, assets] of Object.entries(combine(components))) for (const [name, document] of Object.entries(assets)) {
    const file = path.join(root, 'artemis_enhanced_visuals/compatibility', `bushy_leaves_enhanced+${pack}`, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(document, null, 2) + '\n');
  }
}
module.exports = { combine };
