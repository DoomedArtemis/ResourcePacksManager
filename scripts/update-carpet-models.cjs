// Wool stays flat on top; only the exposed fringe varies, as with moss carpets.
const fs = require('node:fs');
const path = require('node:path');
const { parse, format } = require('./format-json.cjs');
const { png } = require('./moss-legacy-geometry.cjs');
const root = path.join(__dirname, '../resource_packs/better_carpets');
const colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray', 'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black'];
const moss = JSON.parse(fs.readFileSync(path.join(__dirname, '../resource_packs/better_moss/assets/minecraft/models/block/moss_carpet.json'), 'utf8'));
function write(relative, data) {
  const file = path.join(root, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, format(parse(JSON.stringify(data))) + '\n');
}
const surface = structuredClone(moss.elements[0]);
// Model coordinates use 16 units per block: 0.001 blocks = 0.016 units.
// Keep fringe roots clearly outside the supporting block's lighting boundary.
const overhangOffset = 0.016;
const overhangAnchor = 1;
const legacyAngles = [];
function writeOverhang(name, model) {
  const relative = `assets/minecraft/models/block/${name}.json`;
  write(relative, model);
  const legacy = structuredClone(model);
  for (const element of legacy.elements.slice(1)) element.rotation.angle = Math.sign(element.rotation.angle) * 22.5;
  const source = `variants/legacy-angle/${relative}`;
  write(source, legacy);
  legacyAngles.push({ Path: relative, SourcePath: source, BeforeVersion: '1.21.6' });
}
const styles = [
  { name: 'overhanging_carpet', lengths: [2, 2, 2, 2, 2, 2, 2, 2], angle: 20, weight: 4 },
  { name: 'overhanging_carpet_short', lengths: [2, 1, 2, 2, 1, 2, 1, 2], angle: 20, weight: 3 },
  { name: 'overhanging_carpet_uneven', lengths: [2, 2, 1, 2, 2, 1, 2, 2], angle: 20, weight: 1 }
];
const fringe = png(path.join(root, 'assets/minecraft/textures/block/white_carpet_side.png'));
if (fringe.width !== 16 || fringe.height !== 16) throw new Error('Fringe must use a 16x16 Minecraft texture.');
// Shared geometry is safe only when every color has the same opacity mask.
for (const color of colors) {
  const image = png(path.join(root, `assets/minecraft/textures/block/${color}_carpet_side.png`));
  if (image.width !== 16 || image.height !== 16) throw new Error(`Unexpected texture size: ${color}`);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    if (image.opacity(x, y) !== fringe.opacity(x, y)) throw new Error(`Different fringe mask: ${color}`);
  }
}
for (const style of styles) {
  const elements = [structuredClone(surface)];
  for (const [sideIndex, side] of ['north', 'east', 'south', 'west'].entries()) {
    for (let start = 0; start < 16; start++) {
      const length = style.lengths[(Math.floor(start / 2) + sideIndex * 3) % 8];
      const alongX = side === 'north' || side === 'south';
      const negative = side === 'north' || side === 'west';
      const edge = negative ? -overhangOffset : 16 + overhangOffset;
      for (let row = 0; row < length; row++) {
        // Solid-layer carpets in old Minecraft cannot use transparent pixels
        // as holes. Emit only opaque texels as flat, one-model-unit squares.
        if (fringe.opacity(start, row) !== 255) continue;
        const from = alongX ? [start, overhangAnchor - row - 1, edge] : [edge, overhangAnchor - row - 1, start];
        const to = alongX ? [start + 1, overhangAnchor - row, edge] : [edge, overhangAnchor - row, start + 1];
        const faces = {};
        for (const face of alongX ? ['north', 'south'] : ['east', 'west']) {
          faces[face] = { uv: [start, row, start + 1, row + 1], texture: '#side', cullface: side };
        }
        elements.push({ name: side, from, to, faces, rotation: {
          origin: alongX ? [start, overhangAnchor, edge] : [edge, overhangAnchor, start],
          axis: alongX ? 'x' : 'z',
          angle: (side === 'south' || side === 'west' ? -1 : 1) * style.angle,
          rescale: false
        } });
      }
    }
  }
  writeOverhang(style.name, {
    parent: 'minecraft:block/thin_block', textures: { particle: '#wool' }, elements,
    display: moss.display
  });
}
for (const color of colors) {
  for (const style of styles) {
    const suffix = style.name.replace('overhanging_carpet', '');
    const model = { parent: `minecraft:block/${style.name}`, textures: {
      wool: `minecraft:block/${color}_wool`, side: `minecraft:block/${color}_carpet_side`
    } };
    write(suffix ? `assets/minecraft/models/block/${color}_carpet${suffix}.json` : `drop/models/block/${color}_carpet.json`, model);
  }
  write(`assets/minecraft/blockstates/${color}_carpet.json`, { variants: { '': styles.flatMap(style =>
    // Keep the wool UVs aligned with vanilla while rotating the fringe geometry.
    [0, 90, 180, 270].map(y => ({ model: `minecraft:block/${color}_carpet${style.name.replace('overhanging_carpet', '')}`, y, uvlock: true, weight: style.weight }))
  ) } });
  // Explicit item parents keep inventory/hand views on the full-fringe model.
  write(`assets/minecraft/models/item/${color}_carpet.json`, { parent: `minecraft:block/${color}_carpet`, display: moss.display });
}
// Organic edges only: no sprouts, clover, flowers, or other better_moss details.
for (const kind of ['moss', 'pale_moss']) {
  const name = `${kind}_carpet`;
  const pale = kind === 'pale_moss';
  for (const [index, suffix] of ['', '_short', '_uneven'].entries()) {
    const elements = structuredClone(moss.elements);
    for (const [strandIndex, element] of elements.slice(1).entries()) {
      const depthAxis = ['north', 'south'].includes(element.name) ? 2 : 0;
      const edge = ['north', 'west'].includes(element.name) ? -overhangOffset : 16 + overhangOffset;
      element.from[depthAxis] = edge;
      element.to[depthAxis] = edge;
      element.rotation.origin[depthAxis] = edge;
      element.rotation.origin[1] = overhangAnchor;
      element.rotation.angle = Math.sign(element.rotation.angle) * 20;
      const originalLength = -element.from[1];
      const length = index === 1 ? Math.max(1, originalLength - 1)
        : index === 2 ? [1, 3, 2, 4, 1, 2, 3][strandIndex % 7] : originalLength;
      element.from[1] = overhangAnchor - length;
      element.to[1] = overhangAnchor;
      for (const face of Object.values(element.faces)) {
        face.cullface = element.name;
        face.uv[1] = pale ? 16 - length : 0;
        face.uv[3] = pale ? 16 : length;
      }
    }
    writeOverhang(`overhanging_${name}${suffix}`, {
      parent: 'minecraft:block/thin_block', textures: { particle: '#wool' }, elements, display: moss.display
    });
    write(kind === 'moss' && !suffix ? 'drop/models/block/moss_carpet.json'
      : `assets/minecraft/models/block/${name}${suffix}.json`, {
      parent: `minecraft:block/overhanging_${name}${suffix}`,
      textures: { wool: `minecraft:block/${pale ? 'pale_moss_carpet' : 'moss_block'}`,
        side: `minecraft:block/${pale ? 'pale_moss_carpet_side_small' : 'moss_carpet_side'}` }
    });
  }
  const variants = styles.flatMap((style, index) => [0, 90, 180, 270].map(y => ({
    model: `minecraft:block/${name}${['', '_short', '_uneven'][index]}`, y, uvlock: true, weight: style.weight
  })));
  if (!pale) write(`assets/minecraft/blockstates/${name}.json`, { variants: { '': variants } });
  else {
    // Preserve vanilla low/tall wall growth and the empty-state fallback.
    const vanilla = JSON.parse(fs.readFileSync(path.join(__dirname, '../minecraft_assets/blockstates/pale_moss_carpet.json'), 'utf8'));
    for (const part of vanilla.multipart.slice(0, 2)) part.apply = variants;
    write('assets/minecraft/models/block/pale_moss_carpet_growth_none.json', { elements: [] });
    for (const [suffix, depth] of [['short', 2], ['full', 4]]) {
      write(`assets/minecraft/models/block/pale_moss_carpet_growth_${suffix}.json`, {
        textures: { particle: 'minecraft:block/pale_moss_carpet', growth: 'minecraft:block/pale_moss_carpet_side_small' },
        elements: [{ from: [0, 0.008, -depth], to: [16, 0.008, 0],
          faces: { up: { uv: [0, 16 - depth, 16, 16], texture: '#growth' } } }]
      });
    }
    for (const [index, direction] of ['north', 'east', 'south', 'west'].entries()) {
      vanilla.multipart.push({ when: { bottom: 'true', [direction]: 'none' }, apply: [
        { model: 'minecraft:block/pale_moss_carpet_growth_short', y: index * 90, weight: 3 },
        { model: 'minecraft:block/pale_moss_carpet_growth_full', y: index * 90, weight: 2 },
        { model: 'minecraft:block/pale_moss_carpet_growth_none', weight: 5 }
      ] });
    }
    write(`assets/minecraft/blockstates/${name}.json`, vanilla);
  }
  write(`assets/minecraft/models/item/${name}.json`, { parent: `minecraft:block/${name}`, display: moss.display });
}
write('variants/legacy-angle/manifest.json', { FileVariants: legacyAngles });
console.log('Updated carpets with top-anchored overhangs and compatible modern/legacy angles.');
