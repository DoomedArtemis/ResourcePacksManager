const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../resource_packs/better_carpets');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const moss = JSON.parse(fs.readFileSync(path.join(__dirname, '../resource_packs/better_moss/assets/minecraft/models/block/moss_carpet.json'), 'utf8'));
const templates = ['overhanging_carpet', 'overhanging_carpet_short', 'overhanging_carpet_uneven'];
const directions = ['north', 'east', 'south', 'west'];
function assertOutsideBlock(element) {
  const depthAxis = ['north', 'south'].includes(element.name) ? 2 : 0;
  const edge = ['north', 'west'].includes(element.name) ? -0.016 : 16.016;
  assert.equal(element.from[depthAxis], edge, 'Fringe root is 0.001 blocks outside the supporting block');
  assert.equal(element.to[depthAxis], edge);
  assert.equal(element.rotation.origin[depthAxis], edge, 'Rotation preserves the outward offset');
  assert.equal(element.rotation.origin[1], 1, 'Overhang pivots at the carpet top');
}
const { png } = require('./moss-legacy-geometry.cjs');
const fringeImages = fs.readdirSync(path.join(root, 'assets/minecraft/textures/block'))
  .filter(file => file.endsWith('_carpet_side.png') && file !== 'moss_carpet_side.png')
  .map(file => png(path.join(root, 'assets/minecraft/textures/block', file)));
for (const name of templates) {
  const model = read(`assets/minecraft/models/block/${name}.json`);
  assert.deepEqual(model.elements[0], moss.elements[0], 'Continuous vanilla-height carpet surface');
  assert.deepEqual(model.display, moss.display, 'Moss inventory presentation');
  for (const element of model.elements.slice(1)) {
    assert(directions.includes(element.name));
    assertOutsideBlock(element);
    assert(element.from[1] >= -1 && element.to[1] <= 1, 'Fringe lifted exactly one pixel');
    assert(Number.isInteger(element.from[1]) && Number.isInteger(element.to[1]), 'Whole-pixel heights');
    assert([20, -20].includes(element.rotation.angle), 'Slightly steeper modern overhang');
    const depthAxis = ['north', 'south'].includes(element.name) ? 2 : 0;
    assert.equal(element.from[depthAxis], element.to[depthAxis], 'Wool overhangs remain zero-thickness planes');
    assert.equal(Object.keys(element.faces).length, 2, 'Fringe has only its front and back faces');
    for (const face of Object.values(element.faces)) {
      assert.equal(face.cullface, element.name, 'Both sides cull against the same neighboring block');
      assert.equal(face.texture, '#side', 'Preserve the original transparent fringe texture');
      assert(face.uv.every(Number.isInteger), 'Whole-texel UV boundaries');
      const widthAxis = depthAxis === 2 ? 0 : 2;
      assert.equal(face.uv[2] - face.uv[0], element.to[widthAxis] - element.from[widthAxis], 'No horizontal stretch');
      assert.equal(face.uv[3] - face.uv[1], element.to[1] - element.from[1], 'No vertical stretch');
      assert.equal(element.rotation.rescale, false, 'Rotation does not rescale pixels');
      for (const image of fringeImages) {
        for (let y = face.uv[1]; y < face.uv[3]; y++) for (let x = face.uv[0]; x < face.uv[2]; x++) {
          assert.equal(image.opacity(x, y), 255, 'No transparent texels rendered by legacy solid carpets');
        }
      }
      assert(face.uv.every(value => value >= 0 && value <= 16));
    }
  }
}
const states = fs.readdirSync(path.join(root, 'assets/minecraft/blockstates')).filter(file => !['moss_carpet.json', 'pale_moss_carpet.json'].includes(file));
assert.equal(states.length, 16);
for (const file of states) {
  const name = file.replace('.json', '');
  const variants = read(`assets/minecraft/blockstates/${file}`).variants[''];
  assert.equal(variants.length, 12);
  assert.equal(new Set(variants.map(variant => variant.model)).size, 3);
  for (const variant of variants) {
    assert([0, 90, 180, 270].includes(variant.y));
    assert.equal(variant.uvlock, true, 'Wool surface orientation stays fixed across fringe rotations');
    const modelPath = variant.model.replace('minecraft:block/', '');
    const folder = modelPath === name ? 'drop/models/block' : 'assets/minecraft/models/block';
    const model = read(`${folder}/${modelPath}.json`);
    assert(templates.includes(model.parent.replace('minecraft:block/', '')));
    assert.equal(model.textures.wool, `minecraft:block/${name.replace('_carpet', '')}_wool`);
    assert(fs.existsSync(path.join(root, 'assets/minecraft/textures', model.textures.side.replace('minecraft:', '') + '.png')));
  }
  const item = read(`assets/minecraft/models/item/${name}.json`);
  assert.equal(item.parent, `minecraft:block/${name}`);
  assert.deepEqual(item.display, moss.display);
}
for (const kind of ['moss', 'pale_moss']) {
  for (const suffix of ['', '_short', '_uneven']) {
    const model = read(`assets/minecraft/models/block/overhanging_${kind}_carpet${suffix}.json`);
    assert.deepEqual(model.elements[0], moss.elements[0]);
    assert.equal(model.elements.length, 65);
    for (const strand of model.elements.slice(1)) {
      assertOutsideBlock(strand);
      assert(strand.from[1] >= -3 && strand.from[1] <= 0 && strand.to[1] === 1);
      assert.equal(Math.abs(strand.rotation.angle), 20);
      const widthAxis = ['north', 'south'].includes(strand.name) ? 0 : 2;
      for (const face of Object.values(strand.faces)) {
        assert.equal(face.cullface, strand.name);
        assert(face.uv.every(Number.isInteger));
        assert.equal(face.uv[2] - face.uv[0], strand.to[widthAxis] - strand.from[widthAxis]);
        assert.equal(face.uv[3] - face.uv[1], strand.to[1] - strand.from[1]);
      }
    }
  }
  assert.deepEqual(read(`assets/minecraft/models/item/${kind}_carpet.json`).display, moss.display);
}
const pale = read('assets/minecraft/blockstates/pale_moss_carpet.json');
const vanilla = JSON.parse(fs.readFileSync(path.join(__dirname, '../minecraft_assets/blockstates/pale_moss_carpet.json'), 'utf8'));
assert.deepEqual(pale.multipart.slice(2, vanilla.multipart.length), vanilla.multipart.slice(2), 'Preserve low/tall side growth and empty-state fallback');
for (const part of pale.multipart.slice(0, 2)) {
  assert.equal(part.apply.length, 12);
  assert(part.apply.every(variant => variant.uvlock === true));
}
const growth = pale.multipart.slice(vanilla.multipart.length);
assert.equal(growth.length, 4);
for (const [index, part] of growth.entries()) {
  assert.deepEqual(part.when, { bottom: 'true', [directions[index]]: 'none' });
  assert(part.apply.slice(0, 2).every(variant => variant.y === index * 90));
}
for (const suffix of ['short', 'full']) {
  const plane = read(`assets/minecraft/models/block/pale_moss_carpet_growth_${suffix}.json`).elements[0];
  assert(plane.from[2] < 0 && plane.to[2] === 0);
  assert(plane.from[1] > 0 && plane.from[1] < 0.01, 'Growth avoids ground z-fighting');
  const uv = plane.faces.up.uv;
  assert.equal(uv[2] - uv[0], plane.to[0] - plane.from[0]);
  assert.equal(uv[3] - uv[1], plane.to[2] - plane.from[2]);
}
const angleOptions = read('variants/legacy-angle/manifest.json');
assert.equal(angleOptions.FileVariants.length, 9);
for (const rule of angleOptions.FileVariants) {
  assert.equal(rule.BeforeVersion, '1.21.6');
  const modern = read(rule.Path);
  const legacy = read(rule.SourcePath);
  for (const element of modern.elements.slice(1)) element.rotation.angle = Math.sign(element.rotation.angle) * 22.5;
  assert.deepEqual(legacy, modern, 'Legacy changes only the angle, preserving lifted roots and pixel scale');
}
console.log('Validated top anchors, 1:1 pixels, 20-degree modern/22.5-degree legacy angles, and moss growth.');
