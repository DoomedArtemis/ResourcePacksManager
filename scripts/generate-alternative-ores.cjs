// Original geometry and pixel art. No reference-pack assets are read.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { parse, format } = require('./format-json.cjs');
const { fitFaces, atlas } = require('./ore-crystal-textures.cjs');
const { auditSpacing, auditNeighbors } = require('./ore-crystal-spacing.cjs');
const root = path.join(__dirname, '../resource_packs/alternative_ores');
const directions = ['down', 'up', 'north', 'south', 'west', 'east'];
const layouts = [
  [[5.375,5.375],[10.625,10]], [[10,5.375],[5.375,10.625]], [[8,8]],
  [[5.375,5.375],[10.625,5.375],[7,10.625]], [[5.375,8],[10.625,8]],
  [[5.375,5.375],[10.625,9],[5.375,10.625]]
];
const minerals = {
  coal: {}, iron: {}, copper: {}, gold: {}, redstone: {},
  lapis: {}, diamond: {}, emerald: {}, quartz: {}, debris: {}
};
const copperStages=['copper','exposed_copper','weathered_copper','oxidized_copper'];
const textureMinerals=[...Object.keys(minerals),...copperStages.slice(1)];
const ores = [];
for (const mineral of ['coal','iron','copper','gold','redstone','lapis','diamond','emerald']) {
  ores.push({ name: `${mineral}_ore`, mineral, since: mineral === 'copper' ? '1.17' : '1.13' });
  ores.push({ name: `deepslate_${mineral}_ore`, mineral, since: '1.17' });
}
ores.push({ name: 'nether_gold_ore', mineral: 'gold', since: '1.16' },
  { name: 'nether_quartz_ore', mineral: 'quartz', since: '1.13' },
  { name: 'ancient_debris', mineral: 'debris', since: '1.16' });
function write(file, data) {
  const target = path.join(root, file);
  fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, data);
}
function json(file, data) { write(file, format(parse(JSON.stringify(data))) + '\n'); }
function tint(rgb, scale, add = 0) { return rgb.map(v => Math.max(0,Math.min(255,Math.round(v*scale+add)))); }
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function png(width, height, pixels) {
  function chunk(type, bytes) {
    const tag = Buffer.from(type), size = Buffer.alloc(4), crc = Buffer.alloc(4);
    size.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([tag,bytes])));
    return Buffer.concat([size,tag,bytes,crc]);
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height,4);
  header[8] = 8; header[9] = 6;
  const raw = Buffer.alloc(height*(width*4+1));
  for (let y=0;y<height;y++) pixels.copy(raw,y*(width*4+1)+1,y*width*4,(y+1)*width*4);
  return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
}
const texturePixels = {};
function crystalTexture(mineral,kind,patches) {
  const texture=atlas(mineral,kind==='a'?0:1,patches);
  texturePixels[`${mineral}_${kind}`]=texture;
  const image=png(texture.width,texture.height,texture.pixels);
  const name=`${mineral}_crystal_${kind}`;
  write(`assets/minecraft/textures/block/alternative_ores/${name}.png`,image);
  // Every crystal texel is emissive; the rock textures have no emissive overlay.
  write(`assets/minecraft/textures/block/alternative_ores/${name}_e.png`,image);
}
function onFace(face,u,v,d) {
  return { up:[u,16+d,v],down:[u,-d,v],north:[u,v,-d],south:[u,v,16+d],west:[-d,v,u],east:[16+d,v,u] }[face];
}
const crystals={};
function canonicalCrystal(kind) {
  const dimensions=kind==='a'?[5,3,4]:[3,3,5];
  const model={parent:'minecraft:block/block',textures:{particle:`#crystal_${kind}`},elements:[{
    name:`crystal_${kind}`,from:[-dimensions[0]/2,-1,-dimensions[2]/2],to:[dimensions[0]/2,2,dimensions[2]/2],
    light_emission:15,shade:false,
    faces:Object.fromEntries(directions.map(dir=>[dir,{texture:`#crystal_${kind}`}]))
  }]};
  const patches=fitFaces(model);
  return {model,patches};
}
function placedCrystal(kind,face,u,v,angle,axis,name) {
  const source=crystals[kind].model.elements[0];
  const a=onFace(face,u+source.from[0],v+source.from[2],source.from[1]);
  const b=onFace(face,u+source.to[0],v+source.to[2],source.to[1]);
  const normalMap={
    up:{east:'east',west:'west',up:'up',down:'down',north:'north',south:'south'},
    down:{east:'east',west:'west',up:'down',down:'up',north:'north',south:'south'},
    north:{east:'east',west:'west',up:'north',down:'south',north:'down',south:'up'},
    south:{east:'east',west:'west',up:'south',down:'north',north:'down',south:'up'},
    west:{east:'south',west:'north',up:'west',down:'east',north:'down',south:'up'},
    east:{east:'south',west:'north',up:'east',down:'west',north:'down',south:'up'}
  }[face];
  const faces={};
  for(const [localDir,patch] of Object.entries(source.faces)) {
    const worldDir=normalMap[localDir];
    faces[worldDir]={...patch,uv:[...patch.uv],cullface:face};
    const localCorners=faceVertices(source.from,source.to,localDir).map(p=>onFace(face,u+p[0],v+p[2],p[1]));
    const worldCorners=faceVertices(a.map((n,i)=>Math.min(n,b[i])),a.map((n,i)=>Math.max(n,b[i])),worldDir);
    const sourceIndices=worldCorners.map(p=>localCorners.findIndex(q=>q.every((n,i)=>Math.abs(n-p[i])<1e-8)));
    const [u0,v0,u1,v1]=patch.uv,original=[[u0,v0],[u1,v0],[u1,v1],[u0,v1]];
    let found=false;
    for(const flipX of [false,true]) for(const flipY of [false,true]) for(const rotation of [0,90,180,270]) {
      const uv=[flipX?u1:u0,flipY?v1:v0,flipX?u0:u1,flipY?v0:v1];
      const corners=[[uv[0],uv[1]],[uv[2],uv[1]],[uv[2],uv[3]],[uv[0],uv[3]]];
      for(let step=0;step<rotation/90;step++) corners.push(corners.shift());
      if(!found&&corners.every((corner,i)=>corner.every((n,j)=>n===original[sourceIndices[i]][j]))) {
        faces[worldDir].uv=uv;
        if(rotation) faces[worldDir].rotation=rotation;
        found=true;
      }
    }
    if(!found) throw new Error(`Unable to map crystal face ${localDir} to ${worldDir}`);
  }
  const result={name,from:a.map((n,i)=>Math.min(n,b[i])),to:a.map((n,i)=>Math.max(n,b[i])),light_emission:15,shade:false,faces};
  if(angle) result.rotation={origin:onFace(face,u,v,.5),axis,angle,rescale:false};
  return result;
}
function template(variant) {
  const elements=[{name:'plain_rock_core',from:[0,0,0],to:[16,16,16],
    faces:Object.fromEntries(directions.map(dir=>[dir,{uv:[0,0,16,16],texture:['up','down'].includes(dir)?'#top':'#base',cullface:dir}]))}];
  for (const [faceIndex,face] of directions.entries()) {
    // Faces vary independently in crystal count and arrangement.
    const positions=layouts[(variant+faceIndex)%layouts.length];
    for (const [index,position] of positions.entries()) {
      let [u,v]=position;
      if ((faceIndex+variant)%2) [u,v]=[16-v,u];
      const normalAxis=['up','down'].includes(face)?'y':['north','south'].includes(face)?'z':'x';
      const tangentAxes=['x','y','z'].filter(axis=>axis!==normalAxis);
      const axis=tangentAxes[(variant+index+faceIndex)%2];
      const angle=[0,45,-45,22.5,-22.5][(variant+index+faceIndex)%5];
      const kind=(variant+index+faceIndex)%2?'b':'a';
      elements.push(placedCrystal(kind,face,u,v,angle,axis,`${face}_cluster_${index+1}`));
    }
  }
  // Inherit Minecraft's normal item transforms and inventory size.
  return {parent:'minecraft:block/block',ambientocclusion:true,textures:{particle:'#base'},elements};
}
function copperTemplate(variant) {
  const model=template(variant);
  for(const [index,el] of model.elements.slice(1).entries()) {
    const stage=copperStages[(variant+index)%copperStages.length];
    for(const face of Object.values(el.faces)) face.texture=`#crystal_${stage}_${face.texture.slice(-1)}`;
  }
  return model;
}
const models={};
function modelSuffix(variant) { return variant===0?'':variant===1?'_crystals_alt':`_crystals_${variant+1}`; }
function generate() {
  write('assets/minecraft/optifine/emissive.properties','suffix.emissive=_e\n');
  for(const kind of ['a','b']) {
    crystals[kind]=canonicalCrystal(kind);
    json(`assets/minecraft/models/block/alternative_ores/crystal_${kind}.json`,crystals[kind].model);
  }
  for (let variant=0;variant<layouts.length;variant++) {
    const id=`crystal_layout_${variant+1}`; models[id]=template(variant);
    const spacing=auditSpacing(models[id].elements);
    if(spacing.collisions.length||spacing.edgeCrossings.length) throw new Error(`Crystal spacing failed for ${id}: ${JSON.stringify(spacing)}`);
    json(`assets/minecraft/models/block/alternative_ores/${id}.json`,models[id]);
    // World crystals are a separate layer so only they receive block rotations.
    json(`assets/minecraft/models/block/alternative_ores/${id}_overlay.json`,{
      ...models[id],textures:{particle:'#crystal_a'},elements:models[id].elements.slice(1)
    });
  }
  const neighboring=auditNeighbors(Object.values(models));
  if(neighboring.failures.length) throw new Error(`Neighboring crystals overlap: ${JSON.stringify(neighboring.failures.slice(0,3))}`);
  for(let variant=0;variant<layouts.length;variant++) {
    const id=`copper_crystal_layout_${variant+1}`;models[id]=copperTemplate(variant);
    json(`assets/minecraft/models/block/alternative_ores/${id}.json`,models[id]);
    json(`assets/minecraft/models/block/alternative_ores/${id}_overlay.json`,{
      ...models[id],textures:{particle:'#crystal_copper_a'},elements:models[id].elements.slice(1)
    });
  }
  for(const mineral of textureMinerals) {
    for(const kind of ['a','b']) crystalTexture(mineral,kind,crystals[kind].patches);
    // Remove only the obsolete generated color-panel textures.
    for(const oldName of [`${mineral}_crystal`,...layouts.map((_,v)=>`${mineral}_crystals_${v+1}`)]) for(const suffix of ['', '_e']) {
      const oldFile=path.join(root,`assets/minecraft/textures/block/alternative_ores/${oldName}${suffix}.png`);
      if(fs.existsSync(oldFile)) fs.unlinkSync(oldFile);
    }
  }
  for(const shape of ['shard','gem','nugget','blade']) for(let variant=0;variant<6;variant++) for(const suffix of ['', '_overlay']) {
    const oldFile=path.join(root,`assets/minecraft/models/block/alternative_ores/crystal_${shape}_${variant}${suffix}.json`);
    if(fs.existsSync(oldFile)) fs.unlinkSync(oldFile);
  }
  const rules=[];
  for(let variant=0;variant<layouts.length;variant++) for(const suffix of ['', '_overlay'])
    rules.push({Path:`assets/minecraft/models/block/alternative_ores/copper_crystal_layout_${variant+1}${suffix}.json`,MinVersion:'1.17'});
  const debrisBaseFile='assets/minecraft/models/block/alternative_ores/ancient_debris_base.json';
  // The vanilla model ID ancient_debris is also our inventory model. A separate
  // plain base prevents the multipart block from rendering crystals twice.
  json(debrisBaseFile,{parent:'minecraft:block/cube_column',textures:{end:'minecraft:block/ancient_debris_top',side:'minecraft:block/ancient_debris_side'}});
  rules.push({Path:debrisBaseFile,MinVersion:'1.16'});
  for (const ore of ores) {
    const base=ore.name.startsWith('deepslate_')?'deepslate':ore.name.startsWith('nether_')?'netherrack':ore.name==='ancient_debris'?'ancient_debris_side':'stone';
    // Keep each rock face bound to an explicit texture path for legacy model loaders.
    const top=base==='deepslate'?'minecraft:block/deepslate_top':ore.name==='ancient_debris'?'minecraft:block/ancient_debris_top':`minecraft:block/${base}`;
    for (let variant=0;variant<layouts.length;variant++) {
      const file=`assets/minecraft/models/block/${ore.name}${modelSuffix(variant)}.json`;
      const model={parent:`minecraft:block/alternative_ores/${ore.mineral==='copper'?'copper_':''}crystal_layout_${variant+1}`,
        textures:{base:`minecraft:block/${base}`,top,crystal_a:`minecraft:block/alternative_ores/${ore.mineral}_crystal_a`,
          crystal_b:`minecraft:block/alternative_ores/${ore.mineral}_crystal_b`,particle:'#base'}};
      if(ore.mineral==='copper') {
        delete model.textures.crystal_a;delete model.textures.crystal_b;
        for(const stage of copperStages) for(const kind of ['a','b'])
          model.textures[`crystal_${stage}_${kind}`]=`minecraft:block/alternative_ores/${stage}_crystal_${kind}`;
      }
      json(file,model);
      rules.push({Path:file,MinVersion:ore.since});
      const overlayFile=file.replace(/\.json$/,'_overlay.json');
      json(overlayFile,{...model,parent:`${model.parent}_overlay`});
      rules.push({Path:overlayFile,MinVersion:ore.since});
    }
    const file=`assets/minecraft/blockstates/${ore.name}.json`;
    // Always render the vanilla rock model without any transforms. Only the
    // crystal layer rotates; its atlas UVs travel with the crystal geometry.
    const rockModel=ore.name==='ancient_debris'?'alternative_ores/ancient_debris_base':base;
    json(file,{multipart:[
      {apply:{model:`minecraft:block/${rockModel}`}},
      {apply:layouts.flatMap((_,variant)=>[0,90,180,270].map(y=>({model:`minecraft:block/${ore.name}${modelSuffix(variant)}_overlay`,y,uvlock:false})))}
    ]});
    rules.push({Path:file,MinVersion:ore.since});
  }
  for (const [mineral,since] of [...copperStages.map(stage=>[stage,'1.17']),['debris','1.16']])
    for(const kind of ['a','b']) for (const suffix of ['', '_e'])
      rules.push({Path:`assets/minecraft/textures/block/alternative_ores/${mineral}_crystal_${kind}${suffix}.png`,MinVersion:since});
  json('variants/ore-versions.json',{FileRules:rules});
  write('readme.txt',`Alternative Ores

Large, simple 3D mineral crystals on all Minecraft ores, including deepslate
ores, Nether gold, Nether quartz, and ancient debris. One to three broad
crystal pieces on each face, with six layouts and four rotations per block.
Two fixed crystal shapes are reused in different positions and orientations.
Each mineral uses only two editable 32x32 texture nets: crystal_a and crystal_b.
Pixel density is vanilla x16: one texture pixel per model unit. The larger
canvas only stores six faces together; a 5x3 crystal face uses 5x3 pixels.
The faces are arranged as a connected unfolded cube net; see texture-layout.txt.
The matching _e files are generated emissive copies for older renderers.
Copper has normal, exposed, weathered and oxidized crystal textures, with
two textures per stage. Different stages can appear together on one ore block.
Each crystal's shading, bevels and highlights are painted in one shared 3D
surface space, joining across folded edges. Mineral colors are deliberately
restrained, with brighter accents at selected corners and metal reflections.
Each crystal face has fitted artwork: fractured coal, raw iron, weathered copper,
metallic gold, veined redstone, blue lapis, faceted diamond and emerald,
striated quartz, and layered ancient debris. Copper has patina accents.

Stone ores use plain stone; deepslate ores use plain deepslate with its normal
top texture. Nether ores use netherrack. Ancient debris keeps its own base.
The rock textures and base models come from Minecraft or your active texture
pack. Rock keeps its normal orientation; only the crystal layer rotates.

All crystals stay bright in darkness. Minecraft Java 1.21.2 and newer use
vanilla model emission, with no rendering mods required. Earlier versions
need OptiFine or compatible emissive texture support with emissive textures
enabled. Without that support, older versions use normal crystal lighting.
The rock uses normal lighting. Crystal emission does not illuminate nearby
blocks or change gameplay light levels.
Place this pack above other packs that replace ore models or blockstates.

Install the ZIP for your Minecraft version in resourcepacks and enable it
in Options > Resource Packs. Only ores available in that version are included.
`);
  write('texture-layout.txt',`Crystal texture layout (same layout for every mineral)

               TOP
       LEFT   FRONT   RIGHT   BACK
              BOTTOM

Faces touch edge-to-edge, as on an unfolded box. Front is the crystal's
local south face; back is north; left is west; right is east. These directions
describe the original crystal before it is positioned/rotated on an ore.
Crystal A is broad; crystal B is narrow. Face rectangles match each shape.
Both textures use a 32x32 canvas with transparent unused space. Painted
faces use one pixel per model unit (vanilla x16 scale) and are opaque. Highlights
and shading join across shared edges of the folded crystal.

Edit the normal crystal_a/crystal_b PNGs. Update their matching _e files
to keep older-renderer emission synchronized with your artwork.
`);
  createPreviews();
  console.log(`Generated ${ores.length} ores using two crystal shapes, four mixable copper stages, 24 placement variants, and stationary vanilla rock bases.`);
}
function rotated(point,rotation) {
  if (!rotation) return point;
  const p=point.map((n,i)=>n-rotation.origin[i]);
  const [a,b]=rotation.axis==='x'?[1,2]:rotation.axis==='y'?[2,0]:[0,1];
  const theta=rotation.angle*Math.PI/180,u=p[a],v=p[b];
  p[a]=u*Math.cos(theta)-v*Math.sin(theta); p[b]=u*Math.sin(theta)+v*Math.cos(theta);
  return p.map((n,i)=>n+rotation.origin[i]);
}
// Software previews use actual geometry and crystal art with illustrative rock.
function rockPixels(ore) {
  const pixels=Buffer.alloc(1024);
  const rock=ore.name.startsWith('deepslate')?[67,69,74]:ore.name.startsWith('nether')?[108,50,48]:ore.name==='ancient_debris'?[78,55,48]:[119,122,124];
  for (let y=0;y<16;y++) for (let x=0;x<16;x++) pixels.set([...tint(rock,1,((x*19+y*31+x*y*7)%23-11)*1.1),255],(y*16+x)*4);
  return pixels;
}
function faceVertices(from,to,dir) {
  const [x,y,z]=from,[X,Y,Z]=to;
  return {up:[[x,Y,z],[X,Y,z],[X,Y,Z],[x,Y,Z]],down:[[x,y,Z],[X,y,Z],[X,y,z],[x,y,z]],
    north:[[X,Y,z],[x,Y,z],[x,y,z],[X,y,z]],south:[[x,Y,Z],[X,Y,Z],[X,y,Z],[x,y,Z]],
    west:[[x,Y,z],[x,Y,Z],[x,y,Z],[x,y,z]],east:[[X,Y,Z],[X,Y,z],[X,y,z],[X,y,Z]]}[dir];
}
function render(width,height,scenes) {
  const pixels=Buffer.alloc(width*height*4),depths=new Float32Array(width*height).fill(-Infinity);
  for (let i=0;i<width*height;i++) pixels.set([22,27,35,255],i*4);
  for (const scene of scenes) {
    const ore=scene.ore,baseTexture=rockPixels(ore),model=models[`${ore.mineral==='copper'?'copper_':''}crystal_layout_${(scene.variant||0)+1}`];
    const theta=-.65,pitch=.5;
    function project(point) {
      const [x,y,z]=point.map(n=>n-8);
      const horizontal=x*Math.cos(theta)+z*Math.sin(theta),depth=-x*Math.sin(theta)+z*Math.cos(theta);
      return [scene.x+horizontal*scene.scale,scene.y+(-y*Math.cos(pitch)+depth*Math.sin(pitch))*scene.scale,y*Math.sin(pitch)+depth*Math.cos(pitch)];
    }
    for (const el of model.elements) for (const [dir,face] of Object.entries(el.faces)) {
      const vertices=faceVertices(el.from,el.to,dir).map(p=>{
        let point=rotated(p,el.rotation);
        if(el.name!=='plain_rock_core'&&scene.rotation) point=rotated(point,{axis:'y',angle:scene.rotation,origin:[8,8,8]});
        return project(point);
      });
      const alias=face.texture.slice('#crystal_'.length);
      const crystalKey=scene.copperStage?`${scene.copperStage}_${face.texture.slice(-1)}`:alias.length===1?`${ore.mineral}_${alias}`:alias;
      const texture=face.texture.startsWith('#crystal_')?texturePixels[crystalKey]:{width:16,pixels:baseTexture};
      const [u,v,U,V]=face.uv,uv=[[u,v],[U,v],[U,V],[u,V]];
      for(let step=0;step<(face.rotation||0)/90;step++) uv.push(uv.shift());
      const light=el.light_emission===15?1:{up:1,down:.5,north:.65,south:.82,west:.68,east:.88}[dir]*(scene.ambient??1);
      for (const indices of [[0,1,2],[0,2,3]]) {
        const [a,b,c]=indices.map(i=>vertices[i]),area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
        if (Math.abs(area)<.001) continue;
        const x0=Math.max(0,Math.floor(Math.min(a[0],b[0],c[0]))),x1=Math.min(width-1,Math.ceil(Math.max(a[0],b[0],c[0])));
        const y0=Math.max(0,Math.floor(Math.min(a[1],b[1],c[1]))),y1=Math.min(height-1,Math.ceil(Math.max(a[1],b[1],c[1])));
        for (let y=y0;y<=y1;y++) for (let x=x0;x<=x1;x++) {
          const px=x+.5,py=y+.5,wa=((b[0]-px)*(c[1]-py)-(b[1]-py)*(c[0]-px))/area;
          const wb=((c[0]-px)*(a[1]-py)-(c[1]-py)*(a[0]-px))/area,wc=1-wa-wb;
          if (Math.min(wa,wb,wc)<0) continue;
          const depth=wa*a[2]+wb*b[2]+wc*c[2],pos=y*width+x;
          if (depth<=depths[pos]) continue; depths[pos]=depth;
          const tu=Math.max(0,Math.min(texture.width-1,Math.floor((wa*uv[indices[0]][0]+wb*uv[indices[1]][0]+wc*uv[indices[2]][0])*texture.width/16)));
          const tv=Math.max(0,Math.min(texture.width-1,Math.floor((wa*uv[indices[0]][1]+wb*uv[indices[1]][1]+wc*uv[indices[2]][1])*texture.width/16)));
          const texel=(tv*texture.width+tu)*4; pixels.set([...tint([...texture.pixels.subarray(texel,texel+3)],light),255],pos*4);
        }
      }
    }
  }
  return png(width,height,pixels);
}
function createPreviews() {
  const diamond=ores.find(o=>o.name==='diamond_ore');
  write('pack.png',render(256,256,[{ore:diamond,x:128,y:128,scale:8.4}]));
  const previewRoot=path.join(__dirname,'../cache/work/alternative-ores'); fs.mkdirSync(previewRoot,{recursive:true});
  const cards=ores.flatMap(ore=>layouts.map((_,variant)=>({ore,variant,image:render(240,220,[{ore,variant,x:120,y:105,scale:7}]).toString('base64')})));
  const html='<!doctype html><meta charset="utf-8"><title>Alternative Ores - variant preview</title><style>body{background:#161b23;color:#e0e9f4;font:16px system-ui;margin:32px}p{color:#a2b0c2}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}figure{margin:0;background:#1c2430;border-radius:12px;text-align:center;padding:12px}img{width:100%;max-width:240px;image-rendering:pixelated}figcaption{padding-bottom:8px}</style><h1>Alternative Ores - six layouts per ore</h1><p>Each layout also appears in four rotations in Minecraft. Actual crystal geometry and textures; rock surfaces and lighting are illustrative.</p><main>'+cards.map(({ore,variant,image})=>`<figure><img src="data:image/png;base64,${image}" alt="${ore.name} layout ${variant+1}"><figcaption>${ore.name.replaceAll('_',' ')} - layout ${variant+1}</figcaption></figure>`).join('')+'</main>';
  fs.writeFileSync(path.join(previewRoot,'preview.html'),html);
  fs.writeFileSync(path.join(previewRoot,'contact-sheet.png'),render(1000,800,ores.map((ore,i)=>({ore,variant:i%layouts.length,x:100+(i%5)*200,y:95+Math.floor(i/5)*200,scale:5.8}))));
  fs.writeFileSync(path.join(previewRoot,'variant-sheet.png'),render(900,600,layouts.map((_,variant)=>({ore:diamond,variant,x:150+(variant%3)*300,y:145+Math.floor(variant/3)*300,scale:9}))));
  fs.writeFileSync(path.join(previewRoot,'emissive-sheet.png'),render(1000,800,ores.map((ore,i)=>({ore,variant:i%layouts.length,ambient:.1,x:100+(i%5)*200,y:95+Math.floor(i/5)*200,scale:5.8}))));
  const specimens=Object.keys(minerals).map(mineral=>ores.find(ore=>ore.mineral===mineral));
  for(let row=0;row<specimens.length;row++) fs.writeFileSync(path.join(previewRoot,`review-${specimens[row].mineral}.png`),
    render(1200,240,layouts.map((_,variant)=>({ore:specimens[row],variant,x:100+variant*200,y:115,scale:6.4}))));
  const reviewHtml='<!doctype html><meta charset="utf-8"><title>Crystal texture review</title><style>body{background:#161b23;color:#e0e9f4;font:16px system-ui;margin:24px}p{color:#a2b0c2}section{overflow-x:auto}img{width:1200px;max-width:none;image-rendering:pixelated}h2{text-transform:capitalize}</style><h1>Crystal texture review</h1><p>Six layouts per mineral, left to right. Actual crystal artwork and geometry; illustrative rock and lighting.</p>'+specimens.map(ore=>`<h2>${ore.mineral}</h2><section><img src="review-${ore.mineral}.png" alt="All six ${ore.mineral} crystal layouts"></section>`).join('');
  fs.writeFileSync(path.join(previewRoot,'texture-review.html'),reviewHtml);
  const labels={up:'TOP',down:'BOTTOM',south:'FRONT',north:'BACK',west:'LEFT',east:'RIGHT'};
  const netCards=textureMinerals.flatMap(mineral=>['a','b'].map(kind=>{
    const texture=texturePixels[`${mineral}_${kind}`],data=png(texture.width,texture.height,texture.pixels).toString('base64');
    const outlines=crystals[kind].patches.map(p=>`<rect x="${p.x}" y="${p.y}" width="${p.width}" height="${p.height}" fill="none" stroke="white" stroke-width=".2"/><text x="${p.x+p.width/2}" y="${p.y+p.height/2}" text-anchor="middle" dominant-baseline="middle" font-size="1.5" fill="white" stroke="#161b23" stroke-width=".25" paint-order="stroke">${labels[p.dir]}</text>`).join('');
    return `<figure><figcaption>${mineral} - crystal ${kind.toUpperCase()}</figcaption><svg viewBox="0 0 ${texture.width} ${texture.height}"><image width="${texture.width}" height="${texture.height}" href="data:image/png;base64,${data}"/>${outlines}</svg></figure>`;
  })).join('');
  fs.writeFileSync(path.join(previewRoot,'texture-layout.html'),'<!doctype html><meta charset="utf-8"><title>Crystal cube nets</title><style>body{font:16px system-ui;background:#161b23;color:white;margin:24px}main{display:grid;grid-template-columns:repeat(2,minmax(240px,1fr));gap:12px}figure{margin:0;background:#242b35;padding:12px}svg{width:100%;image-rendering:pixelated}figcaption{text-transform:capitalize}</style><h1>Crystal texture nets</h1><p>Labels appear only in this guide. The PNGs contain artwork and transparent unused canvas.</p><main>'+netCards+'</main>');
  fs.writeFileSync(path.join(previewRoot,'rotation-review.png'),render(1000,750,
    [0,90,180,270].flatMap((rotation,row)=>[diamond,...specimens.filter(ore=>['lapis','iron','gold','emerald'].includes(ore.mineral))]
      .map((ore,column)=>({ore,rotation,variant:2,x:100+column*200,y:90+row*185,scale:5.5})))));
  const copper=ores.find(ore=>ore.name==='copper_ore'),deepslate=ores.find(ore=>ore.name==='deepslate_copper_ore');
  const oxidationPreview=render(1000,400,[copper,deepslate].flatMap((ore,row)=>
    [...copperStages,null].map((stage,column)=>({ore,copperStage:stage,variant:1,x:100+column*200,y:95+row*200,scale:5.8}))));
  fs.writeFileSync(path.join(previewRoot,'copper-oxidation.png'),oxidationPreview);
  fs.writeFileSync(path.join(previewRoot,'copper-oxidation.html'),'<!doctype html><meta charset="utf-8"><title>Copper crystal oxidation</title><style>body{background:#161b23;color:white;font:16px system-ui;margin:24px}img{max-width:100%;image-rendering:pixelated}</style><h1>Copper crystal oxidation</h1><p>Left to right: normal, exposed, weathered, oxidized, and mixed. Stone above; deepslate below. Same crystal shapes and vanilla pixel density.</p><img src="copper-oxidation.png" alt="Four copper oxidation stages and mixed-stage ore blocks">');
}
if (require.main===module) generate();
module.exports={ores,minerals,textureMinerals,copperStages,root,rotated};
