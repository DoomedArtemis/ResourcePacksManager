const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const { box, separation, auditSpacing, auditNeighbors } = require('./ore-crystal-spacing.cjs');
const { audit, auditRotations } = require('./audit-ore-textures.cjs');
const { surfacePoint } = require('./ore-crystal-textures.cjs');
const { ores, textureMinerals, copperStages, root, rotated } = require('./generate-alternative-ores.cjs');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const manifest = read('variants/ore-versions.json');
const sides = ['up', 'down', 'north', 'south', 'east', 'west'];
const introduction = new Map(manifest.FileRules.map(rule => [rule.Path, rule.MinVersion]));
const versionOrder = ['1.13', '1.16', '1.17', '1.21.11', '26.2'];
const vanillaModels=JSON.parse(fs.readFileSync(path.join(__dirname,'../cache/vanilla-asset-catalogs/dependency-data/1.21.11.json'),'utf8').replace(/^\uFEFF/,'')).JsonAssets;
// Verify the geometry check catches overlap and measures tilted-box clearance.
const probe=box({from:[0,0,0],to:[2,2,2],rotation:{axis:'y',angle:45,origin:[1,1,1]}});
assert(separation(probe,probe)<0,'Coincident crystals must fail the overlap check');
const separated={...probe,center:probe.center.map((n,i)=>n+probe.axes[0][i]*2.5)};
assert(Math.abs(separation(probe,separated)-.5)<1e-8,'Measure separation along rotated axes');
function effectiveModel(id, textures = {}, vanillaOnly=false) {
  if(!id.includes(':')) id=`minecraft:${id}`;
  const modelFile=`assets/minecraft/models/${id.split(':')[1]}.json`;
  const model = !vanillaOnly&&fs.existsSync(path.join(root,modelFile))?read(modelFile):JSON.parse(vanillaModels[modelFile]);
  textures = { ...model.textures, ...textures };
  if (model.elements) return { ...model, textures };
  return effectiveModel(model.parent, textures,vanillaOnly);
}
function resolveTexture(key, textures, chain = []) {
  if (!key.startsWith('#')) return key;
  assert(!chain.includes(key), `Texture reference cycle: ${chain} -> ${key}`);
  assert(textures[key.slice(1)], `Missing texture variable ${key}`);
  return resolveTexture(textures[key.slice(1)], textures, [...chain, key]);
}
const validatedImages=new Map();
function validatePng(file) {
  if(validatedImages.has(file)) return validatedImages.get(file);
  const bytes = fs.readFileSync(file);
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20);
  assert.equal(width,32); assert.equal(height,32);
  assert.equal(bytes[24], 8); assert.equal(bytes[25], 6);
  const chunks = [];
  for (let pos = 8; pos < bytes.length;) {
    const size = bytes.readUInt32BE(pos);
    if (bytes.toString('ascii', pos + 4, pos + 8) === 'IDAT') chunks.push(bytes.subarray(pos + 8, pos + 8 + size));
    pos += size + 12;
  }
  const raw = zlib.inflateSync(Buffer.concat(chunks));
  const stride=width*4+1;
  assert.equal(raw.length, height * stride);
  for (let y = 0; y < height; y++) {
    assert.equal(raw[y * stride], 0);
    for (let x = 0; x < width; x++) assert([0,255].includes(raw[y * stride + 1 + x * 4 + 3]), 'Artwork is opaque; unused net canvas is transparent');
  }
  const result={width,height,pixel:(x,y)=>raw.subarray(y*stride+1+x*4,y*stride+1+x*4+4)};validatedImages.set(file,result);return result;
}
assert.equal(ores.length, 19);
for(const kind of ['a','b']) {
  const faces=read(`assets/minecraft/models/block/alternative_ores/crystal_${kind}.json`).elements[0].faces;
  const rect=dir=>faces[dir].uv.map(n=>n*2);
  const front=rect('south'),top=rect('up'),bottom=rect('down'),left=rect('west'),right=rect('east'),back=rect('north');
  assert.equal(top[0],front[0]);assert.equal(top[2],front[2]);assert.equal(top[3],front[1]);
  assert.equal(bottom[0],front[0]);assert.equal(bottom[2],front[2]);assert.equal(bottom[1],front[3]);
  assert.equal(left[2],front[0]);assert.equal(right[0],front[2]);assert.equal(back[0],right[2]);
  for(const side of [left,right,back]) {assert.equal(side[1],front[1]);assert.equal(side[3],front[3]);}
}
assert.equal(fs.readFileSync(path.join(root,'assets/minecraft/optifine/emissive.properties'),'utf8').trim(), 'suffix.emissive=_e');
for (const [mineral,since] of [...copperStages.map(stage=>[stage,'1.17']),['debris','1.16']])
  for(const kind of ['a','b']) for(const suffix of ['', '_e'])
    assert.equal(introduction.get(`assets/minecraft/textures/block/alternative_ores/${mineral}_crystal_${kind}${suffix}.png`),since);
assert.equal(introduction.get('assets/minecraft/models/block/alternative_ores/ancient_debris_base.json'),'1.16');
for (const ore of ores) {
  const stateFile = `assets/minecraft/blockstates/${ore.name}.json`;
  assert.equal(introduction.get(stateFile), ore.since);
  const blockstate=read(stateFile);
  assert.equal(blockstate.multipart.length,2,'Separate stationary rock and varied crystal layers');
  const rock=ore.name.startsWith('deepslate_')?'deepslate':ore.name.startsWith('nether_')?'netherrack':ore.name==='ancient_debris'?'alternative_ores/ancient_debris_base':'stone';
  assert.deepEqual(blockstate.multipart[0],{apply:{model:`minecraft:block/${rock}`}},'Use the normal vanilla rock model with no rotation or texture transform');
  const resolvedBase=effectiveModel(blockstate.multipart[0].apply.model);
  assert.equal(resolvedBase.elements.length,1,'The resolved world base must be a plain cube, never a crystal-bearing item model');
  for(const face of Object.values(resolvedBase.elements[0].faces)) {
    assert(!resolveTexture(face.texture,resolvedBase.textures).includes('crystal'),'No second crystal layer hidden in the base model');
  }
  if(ore.name==='ancient_debris') {
    const nativeBase=effectiveModel('minecraft:block/ancient_debris',{},true);
    assert.deepEqual(resolvedBase.elements,nativeBase.elements,'Plain debris base matches vanilla geometry and face orientation');
    assert.deepEqual(resolvedBase.textures,nativeBase.textures,'Plain debris base matches vanilla textures');
  }
  const variants = blockstate.multipart[1].apply;
  assert.equal(variants.length, 24, 'Six layouts with four block rotations each');
  const modelIds = [...new Set(variants.map(variant => variant.model))];
  assert.equal(modelIds.length, 6);
  const geometries = new Set();
  const textureIds=new Set();
  for (const id of modelIds) {
    const rotations = variants.filter(v => v.model === id);
    assert.deepEqual(rotations.map(v => v.y).sort((a,b) => a-b), [0,90,180,270]);
    assert(rotations.every(v => v.uvlock === false), 'Atlas patches must rotate with their crystals');
    const variant = { model: id };
    assert.equal(introduction.get(`assets/minecraft/models/${variant.model.split(':')[1]}.json`), ore.since);
    const overlay=effectiveModel(variant.model);
    const itemModelId=variant.model.replace(/_overlay$/,'');
    const model = effectiveModel(itemModelId);
    assert.equal(introduction.get(`assets/minecraft/models/${itemModelId.split(':')[1]}.json`),ore.since);
    assert.deepEqual(overlay.elements,model.elements.slice(1),'The rotated world layer contains only crystals');
    const fullScene=auditSpacing([{...resolvedBase.elements[0],name:'plain_rock_core'},...overlay.elements]);
    assert.equal(fullScene.collisions.length,0,`Resolved multipart scene clips for ${ore.name}`);
    assert(overlay.elements.every(el=>el.name!=='plain_rock_core'),'Never rotate rock in the crystal layer');
    assert.equal(model.parent,'minecraft:block/block','Inherit vanilla item transforms');
    assert.equal(model.display,undefined,'No reduced inventory or held-item scale');
    for(const el of model.elements.slice(1)) for(const face of Object.values(el.faces)) textureIds.add(resolveTexture(face.texture,model.textures));
    if(ore.mineral==='copper') {
      const stages=new Set(model.elements.slice(1).map(el=>Object.values(el.faces)[0].texture.replace(/^#crystal_/,'').slice(0,-2)));
      assert.deepEqual([...stages].sort(),[...copperStages].sort(),'Copper blocks combine all four oxidation stages');
      const copperParent=read(`assets/minecraft/models/${itemModelId.split(':')[1]}.json`).parent;
      const shared=read(`assets/minecraft/models/${copperParent.split(':')[1].replace('copper_crystal_layout','crystal_layout')}.json`);
      const geometry=elements=>elements.map(el=>({from:el.from,to:el.to,rotation:el.rotation}));
      assert.deepEqual(geometry(model.elements),geometry(shared.elements),'Copper colors reuse the proven collision-free crystal placements');
    }
    const core = model.elements[0];
    assert.equal(core.light_emission ?? 0, 0, 'Rock is not emissive');
    assert.notEqual(core.shade, false, 'Rock retains normal directional lighting');
    assert.deepEqual(core.from, [0, 0, 0]); assert.deepEqual(core.to, [16, 16, 16]);
    assert(model.elements.length <= 19, 'At most three single-piece crystals per face');
    geometries.add(JSON.stringify(model.elements));
    const faceCounts = new Set();
    for (const dir of sides) {
      assert.equal(core.faces[dir].cullface, dir);
      const isTop = ['up', 'down'].includes(dir);
      assert(!model.textures[core.faces[dir].texture.slice(1)].startsWith('#'),
        'Rock face bindings must be direct texture paths for legacy item model loaders');
      const expected = ore.name.startsWith('deepslate_') ? (isTop ? 'deepslate_top' : 'deepslate')
        : ore.name.startsWith('nether_') ? 'netherrack'
        : ore.name === 'ancient_debris' ? `ancient_debris_${isTop ? 'top' : 'side'}` : 'stone';
      assert.equal(resolveTexture(core.faces[dir].texture, model.textures), `minecraft:block/${expected}`);
      const cluster = model.elements.slice(1).filter(el => el.name.startsWith(`${dir}_cluster_`));
      assert(cluster.length >= 1 && cluster.length <= 3, 'One to three broad, single-piece crystals on each face');
      faceCounts.add(cluster.length);
      for (const el of cluster) {
        const dimensions = el.from.map((n,i) => el.to[i] - n).sort((a,b) => a-b);
        const kind=Object.values(el.faces)[0].texture.slice(-1);
        const material=Object.values(el.faces)[0].texture;
        assert(Object.values(el.faces).every(face=>face.texture===material),'One reusable material per complete crystal');
        assert.deepEqual(dimensions,kind==='a'?[3,4,5]:[3,3,5],'Only two fixed crystal shapes, without scaling');
      }
      for (const el of cluster) for (const face of Object.values(el.faces)) assert.equal(face.cullface, dir, 'Hide crystals against solid neighbors');
    }
    assert.equal(faceCounts.size, 3, 'Faces vary between one, two, and three crystals');
    for (const el of model.elements) {
      if (el !== core) {
        assert.equal(el.light_emission, 15, 'Every crystal is fully emissive in vanilla 1.21.2+');
        assert.equal(el.shade, false, 'Crystal faces remain bright regardless of direction');
      }
      assert(el.from.every((n, i) => n < el.to[i]));
      if (el.rotation) {
        assert([-45, -22.5, 0, 22.5, 45].includes(el.rotation.angle), 'Legacy-compatible angle');
        assert.equal(el.rotation.rescale, false);
      }
      for (let mask = 0; mask < 8; mask++) {
        const vertex = rotated(el.from.map((n,i) => mask & (1 << i) ? el.to[i] : n), el.rotation);
        assert(vertex.every(n => n >= -4 && n <= 20), 'Keep protrusions small and inside Minecraft model bounds');
      }
      for (const [dir,face] of Object.entries(el.faces)) {
        assert(face.uv.every(n => n >= 0 && n <= 16));
        const texture = resolveTexture(face.texture, model.textures);
        if (texture.includes('/alternative_ores/')) {
          const file = path.join(root, `assets/minecraft/textures/${texture.split(':')[1]}.png`);
          assert(fs.existsSync(file), `Missing custom texture ${texture}`);
          const image=validatePng(file);
          const axes=['up','down'].includes(dir)?[0,2]:['north','south'].includes(dir)?[0,1]:[2,1];
          const dimensions=axes.map(axis=>el.to[axis]-el.from[axis]);
          const texels=[face.uv[2]-face.uv[0],face.uv[3]-face.uv[1]].map(n=>Math.abs(n)*image.width/16);
          if((face.rotation||0)%180===90) texels.reverse();
          assert(texels.every((n,i)=>Math.abs(n-dimensions[i])<1e-8),'Every crystal face uses exactly one texel per model unit: vanilla x16 pixel size');
          const overlay = file.replace(/\.png$/, '_e.png');
          assert(fs.existsSync(overlay), `Missing emissive overlay for ${texture}`);
          assert.deepEqual(fs.readFileSync(overlay),fs.readFileSync(file),'Every crystal pixel has a matching emissive overlay');
        }
      }
    }
  }
  assert.equal(geometries.size, 6, 'All six layouts have distinct geometry');
  assert.equal(textureIds.size,ore.mineral==='copper'?8:2,'Only the two shapes per mineral/stage are used');
}
const artHashes=new Set([...validatedImages.keys()].map(file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')));
assert.equal(artHashes.size,26,'Two editable sheets per mineral, with three additional copper stages');
for(const mineral of textureMinerals) for(const kind of ['a','b']) {
  const faces=read(`assets/minecraft/models/block/alternative_ores/crystal_${kind}.json`).elements[0].faces;
  const image=validatePng(path.join(root,`assets/minecraft/textures/block/alternative_ores/${mineral}_crystal_${kind}.png`));
  const seamColors=new Map();
  for(const [dir,face] of Object.entries(faces)) {
    const [x0,y0,x1,y1]=face.uv.map(n=>Math.round(n*image.width/16)),w=x1-x0,h=y1-y0;
    for(let y=0;y<h;y++) for(let x=0;x<w;x++) {
      if(x!==0&&y!==0&&x!==w-1&&y!==h-1) continue;
      const key=surfacePoint(dir,x/(w-1),y/(h-1)).map(n=>n.toFixed(7)).join(',');
      const color=image.pixel(x0+x,y0+y).toString('hex');
      if(seamColors.has(key)) assert.equal(color,seamColors.get(key),`Folded edge colors must join: ${mineral}/${kind}/${dir}`);
      else seamColors.set(key,color);
    }
  }
}
const textureFiles=fs.readdirSync(path.join(root,'assets/minecraft/textures/block/alternative_ores')).filter(file=>file.includes('_crystal')&&file.endsWith('.png'));
assert.equal(textureFiles.length,52,'Twenty-six editable textures and their emissive copies; no obsolete sheets');
assert(textureFiles.every(file=>/^(coal|iron|copper|exposed_copper|weathered_copper|oxidized_copper|gold|redstone|lapis|diamond|emerald|quartz|debris)_crystal_[ab](_e)?\.png$/.test(file)));
const placementModels=Array.from({length:6},(_,i)=>read(`assets/minecraft/models/block/alternative_ores/crystal_layout_${i+1}.json`));
for(const [index,model] of placementModels.entries()) {
  const spacing=auditSpacing(model.elements);
  assert.equal(spacing.collisions.length,0,`Crystal overlap or insufficient clearance in layout ${index+1}`);
  assert.equal(spacing.edgeCrossings.length,0,`Crystal footprint crosses a block edge in layout ${index+1}`);
}
const neighborSpacing=auditNeighbors(placementModels);
assert.equal(neighborSpacing.pairs,2352480,'Cover all layouts, rotations and 26 neighboring block positions');
assert.equal(neighborSpacing.failures.length,0,'Visible crystals on neighboring ore blocks need clearance');
const paintedFaces=audit();
assert.equal(paintedFaces.length,6084,'Review every mineral/stage, layout, crystal size and face');
for(const face of paintedFaces) {
  const label=`${face.mineral}/${face.variant}/${face.piece}/${face.dir}`;
  assert(face.colors>=2,`Unpainted solid-color patch: ${label}`);
  assert.equal(face.incomplete,0,`Incomplete patch: ${label}`);
  assert.equal(face.isolated,0,`Isolated detail pixels: ${label}`);
  if(face.mineral==='lapis') assert.equal(face.warm,0,`Non-blue inclusion in lapis: ${label}`);
}
const rotatedFaces=auditRotations();
assert.equal(rotatedFaces.length,11856,'Check atlas sampling across every ore/layout/block rotation');
assert(rotatedFaces.every(face=>face.colors>=2),'Rotated crystal faces must sample painted patches, not solid atlas background');
// Verify external vanilla dependencies against the repository's official Mojang catalogs.
for (const version of versionOrder) {
  const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, `../cache/vanilla-asset-catalogs/${version}.json`), 'utf8').replace(/^\uFEFF/, ''));
  const vanillaPaths = new Set(Object.values(catalog.byFileName).flat());
  const supported = ores.filter(o => versionOrder.indexOf(o.since) <= versionOrder.indexOf(version));
  assert.equal(supported.length, version === '1.13' ? 8 : version === '1.16' ? 10 : 19);
  for (const ore of supported) {
    assert(vanillaPaths.has(`assets/minecraft/blockstates/${ore.name}.json`), `${ore.name} absent in ${version}`);
    const stationaryModel=read(`assets/minecraft/blockstates/${ore.name}.json`).multipart[0].apply.model;
    const stationaryPath=`assets/minecraft/models/${stationaryModel.split(':')[1]}.json`;
    assert(vanillaPaths.has(stationaryPath)||fs.existsSync(path.join(root,stationaryPath)),`Missing base ${stationaryModel} in ${version}`);
    const model = effectiveModel(`minecraft:block/${ore.name}`);
    for (const face of Object.values(model.elements[0].faces)) {
      const texture = resolveTexture(face.texture, model.textures);
      assert(vanillaPaths.has(`assets/minecraft/textures/${texture.split(':')[1]}.png`), `${texture} absent in ${version}`);
    }
  }
}
console.log('PASS: Two connected cube-net textures per mineral; fitted opaque faces, matching emissive copies, all layouts/rotations, crystal clearance, stationary vanilla rock and normal item scale.');
