// Original foliage geometry. No artwork or model data from reference packs is used.
const fs = require('node:fs');
const path = require('node:path');
const { accents, accentTypes, sprites, spritePng, detailModel, detailChoices } = require('./bushy-leaves-enhanced-details.cjs');
const root = path.resolve(__dirname, '../resource_packs/bushy_leaves_enhanced');
const directions = ['down', 'up', 'north', 'south', 'west', 'east'];
const species = {
  oak: ['broad', true, '1.13'], birch: ['airy', true, '1.13'],
  spruce: ['conifer', true, '1.13'], jungle: ['lush', true, '1.13'],
  acacia: ['airy', true, '1.13'], dark_oak: ['broad', true, '1.13'],
  azalea: ['blossom', false, '1.17'], flowering_azalea: ['blossom', false, '1.17'],
  mangrove: ['lush', true, '1.19'], cherry: ['blossom', true, '1.19.4'],
  pale_oak: ['airy', true, '1.21.2'],
  orange_poplar: ['airy', false, '26.3'], yellow_poplar: ['airy', false, '26.3'],
  red_poplar: ['airy', false, '26.3'],
};

function write(relative, data) {
  const destination = path.join(root, relative);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, JSON.stringify(data, null, 2) + '\n');
}

// Broad, projecting fans restore a full canopy silhouette. Rotation roots stay
// on the core boundary, while each fan crosses it and extends out into the air.
function geometry(profile = 'broad', layout = 0, tinted = true) {
  const settings = {
    broad: [13, 11, 1.75], airy: [11, 9.5, 1.5], conifer: [9, 13, 1.5],
    lush: [14, 12, 2], blossom: [12, 10.5, 1.75],
  };
  if (!settings[profile] || ![0, 1, 2].includes(layout)) throw Error('Unknown foliage layout');
  const [width, height, projection] = settings[profile];
  const face = (direction, uv = [0, 0, 16, 16]) => ({
    uv, texture: '#all', cullface: direction, ...(tinted ? { tintindex: 0 } : {}),
  });
  const elements = [{
    from: [0, 0, 0], to: [16, 16, 16],
    faces: Object.fromEntries(directions.map(d => [d, face(d)])),
  }];
  for (const [index, direction] of directions.entries()) {
    const normal = index < 2 ? 1 : index < 4 ? 2 : 0;
    const [u, v] = normal === 1 ? [0, 2] : normal === 2 ? [0, 1] : [2, 1];
    const positive = index % 2 === 1;
    for (let spray = 0; spray < 2; spray++) {
      // Asymmetric attachment points, rather than broad parallel panels. The
      // second fan leans on the other tangent axis, filling edge-on viewing gaps.
      const shift = ((index + layout * 2 + spray) % 3 - 1) * 0.5;
      const anchors = [[4.5, 5.5], [11.5, 9], [7.5, 12]];
      const [a, b] = anchors[(spray + layout) % anchors.length];
      const w = width - ((spray + layout) % 3) * 0.5;
      const h = height - ((spray + index) % 2) * 0.5;
      const origin = [0, 0, 0];
      origin[u] = a + shift;
      origin[v] = b - shift;
      origin[normal] = positive ? 16 : 0;
      const from = [...origin], to = [...origin];
      from[normal] = to[normal] = origin[normal] + (positive ? projection : -projection);
      from[u] -= w / 2; to[u] += w / 2;
      from[v] -= h / 2; to[v] += h / 2;
      // Match UV span to physical span. A pixel has the same size on the core
      // and the fans, including higher-resolution and animated source textures.
      const uvU = (index * 3 + layout * 2 + spray) % (Math.floor(16 - w) + 1);
      const uvV = (index + layout * 3 + spray * 2) % (Math.floor(16 - h) + 1);
      const pair = normal === 1 ? ['up', 'down'] : normal === 2 ? ['north', 'south'] : ['west', 'east'];
      const rotationAxis = ['x', 'y', 'z'][spray === 1 ? u : v];
      const angle = ((index + spray + layout) % 2 ? -1 : 1) * 45;
      const rotation = { origin, axis: rotationAxis, angle, rescale: false };
      const [aAxis] = { x: [1, 2], y: [2, 0], z: [0, 1] }[rotationAxis];
      const tipDirection = (positive ? 1 : -1) * (normal === aAxis ? -1 : 1) * Math.sign(angle);
      const lengthAxis = spray === 1 ? v : u;
      const crossAxis = spray === 1 ? u : v;
      const cut = tipDirection > 0 ? to[lengthAxis] - 2 : from[lengthAxis] + 2;
      const bodyFrom = [...from], bodyTo = [...to], tipFrom = [...from], tipTo = [...to];
      if (tipDirection > 0) { bodyTo[lengthAxis] = cut; tipFrom[lengthAxis] = cut; }
      else { bodyFrom[lengthAxis] = cut; tipTo[lengthAxis] = cut; }
      // A narrower final two-pixel band cuts the blunt corners off the fan.
      // The two rectangles share an edge and UVs; they are one flat leaf spray,
      // with no overlap, detached pieces, added volume or stretched pixels.
      tipFrom[crossAxis] += 1.25; tipTo[crossAxis] -= 1.25;
      for (const [partFrom, partTo] of [[bodyFrom, bodyTo], [tipFrom, tipTo]]) {
        const uv = [
          uvU + (normal === 2 ? to[u] - partTo[u] : partFrom[u] - from[u]),
          uvV + (normal === 1 ? partFrom[v] - from[v] : to[v] - partTo[v]),
          uvU + (normal === 2 ? to[u] - partFrom[u] : partTo[u] - from[u]),
          uvV + (normal === 1 ? partTo[v] - from[v] : to[v] - partFrom[v]),
        ];
        const faces = { [pair[0]]: face(direction, uv), [pair[1]]: face(direction, [uv[2], uv[1], uv[0], uv[3]]) };
        elements.push({ from: partFrom, to: partTo, shade: false, rotation, faces });
      }
    }
  }
  return { parent: 'minecraft:block/block', textures: { particle: '#all' }, elements };
}

function generate() {
  for (const sprite of Object.keys(sprites)) {
    const destination = path.join(root, `assets/bushy_leaves_enhanced/textures/block/details/${sprite}.png`);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, spritePng(sprite));
  }
  write('assets/bushy_leaves_enhanced/models/block/details/none.json', {
    parent: 'minecraft:block/block', textures: { particle: 'minecraft:block/oak_leaves' }, elements: [],
  });
  for (const name of Object.keys(accents)) for (const type of accentTypes(name)) for (const placement of type.placements) {
    write(`assets/bushy_leaves_enhanced/models/block/details/${type.modelPrefix}_${placement}.json`, detailModel(name, placement, type.sprite));
  }
  const profiles = [...new Set(Object.values(species).map(s => s[0]))];
  for (const profile of profiles) for (let layout = 0; layout < 3; layout++) {
    for (const tinted of [true, false]) {
      write(`assets/bushy_leaves_enhanced/models/block/${profile}_${layout}${tinted ? '' : '_untinted'}.json`, geometry(profile, layout, tinted));
    }
  }
  // Unknown modded species inherit this file automatically if they use the
  // standard leaves parent. Do not touch cube_all: it is shared by solid blocks.
  write('assets/minecraft/models/block/leaves.json', geometry());
  const rules = [];
  for (const [name, [profile, tinted, minimum]] of Object.entries(species)) {
    const variants = [];
    for (let layout = 0; layout < 3; layout++) {
      const modelName = `bushy_leaves_enhanced/${name}_${layout}`;
      write(`assets/minecraft/models/block/${modelName}.json`, {
        parent: `bushy_leaves_enhanced:block/${profile}_${layout}${tinted ? '' : '_untinted'}`,
        textures: { all: `minecraft:block/${name}_leaves` },
      });
      for (const y of [0, 90, 180, 270]) variants.push({ model: `minecraft:block/${modelName}`, y, uvlock: false, weight: layout === 0 ? 2 : 1 });
    }
    // Keep foliage and rare accents independent. Empty overlay choices add no
    // quads; ornaments add two crossed planes and blossoms add one surface plane.
    write(`assets/minecraft/blockstates/${name}_leaves.json`, accents[name]
      ? { multipart: [{ apply: variants }, { apply: detailChoices(name) }] }
      : { variants: { '': variants } });
    write(`assets/minecraft/models/block/${name}_leaves.json`, {
      parent: `minecraft:block/bushy_leaves_enhanced/${name}_0`,
      textures: { all: `minecraft:block/${name}_leaves` },
    });
    for (const relative of [`assets/minecraft/blockstates/${name}_leaves.json`,
      `assets/minecraft/models/block/${name}_leaves.json`,
      ...[0, 1, 2].map(layout => `assets/minecraft/models/block/bushy_leaves_enhanced/${name}_${layout}.json`)]) {
      rules.push({ Path: relative, MinVersion: minimum });
    }
    if (accents[name]) for (const type of accentTypes(name)) for (const placement of type.placements) {
      rules.push({ Path: `assets/bushy_leaves_enhanced/models/block/details/${type.modelPrefix}_${placement}.json`, MinVersion: minimum });
    }
  }
  write('variants/leaves-versions.json', { FileRules: rules });
  console.log(`Generated ${Object.keys(species).length} species with rooted, tapered flat foliage fans; 54 quads per block before neighbour culling.`);
}

if (require.main === module) generate();
module.exports = { geometry, generate, species, directions };
