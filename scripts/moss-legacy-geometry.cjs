const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const formatter = require('./format-json.cjs');
const jsonText = value => formatter.format(formatter.parse(JSON.stringify(value))) + '\n';

const root = path.resolve(__dirname, '..');
const pack = path.join(root, 'resource_packs/better_moss');
const configPath = path.join(root, 'cache/transparency/config.json');
const config = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {versions:[],rules:[]};
const versions = config.versions;
const order = version => versions.indexOf(version);
const phases = [
  { id: '1.17', vanilla: '1.17', before: '1.20' },
  { id: '1.20', vanilla: '1.20', before: '1.21.4' },
  { id: '1.21.4', vanilla: '1.21.4', before: '1.21.5' },
  { id: '1.21.5', vanilla: '1.21.5', before: '1.21.11' },
  { id: '1.21.11', vanilla: '1.21.11', before: '26.1' }
];
const clone = value => JSON.parse(JSON.stringify(value));
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(file) : [file];
  });
}
function enabled(relative, version) {
  for (const rule of config.rules) {
    if (relative !== rule.Path && !relative.startsWith(rule.Path)) continue;
    if (rule.MinVersion && order(version) < order(rule.MinVersion)) return false;
    if (rule.BeforeVersion && order(version) >= order(rule.BeforeVersion)) return false;
  }
  return true;
}
function asset(id, kind, extension, phase) {
  const relative = `assets/${id.replace(':', `/${kind}/`)}.${extension}`;
  const local = path.join(pack, relative);
  const variant = (config.variants || []).find(rule => rule.Path === relative &&
    (!rule.MinVersion || order(phase.id) >= order(rule.MinVersion)) &&
    (!rule.BeforeVersion || order(phase.id) < order(rule.BeforeVersion)));
  if (variant) return path.join(pack, variant.SourcePath);
  if (fs.existsSync(local) && enabled(relative, phase.id)) return local;
  const vanilla = path.join(root, 'cache/transparency/vanilla', phase.vanilla, relative);
  if (!fs.existsSync(vanilla)) throw new Error(`Missing ${relative} for ${phase.id}`);
  return vanilla;
}

// Read PNG pixels without resampling or changing the source images.
function png(file) {
  const bytes = fs.readFileSync(file);
  if (!bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error(`Not PNG: ${file}`);
  let width, height, depth, color, palette, alpha;
  const compressed = [];
  for (let offset = 8; offset < bytes.length;) {
    const size = bytes.readUInt32BE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + size);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4); depth = data[8]; color = data[9];
      if (data[12] !== 0) throw new Error(`Interlaced PNG: ${file}`);
    }
    if (type === 'PLTE') palette = data;
    if (type === 'tRNS') alpha = data;
    if (type === 'IDAT') compressed.push(data);
    offset += size + 12;
  }
  if (depth !== 8 && !([0,3].includes(color) && [1,2,4].includes(depth))) throw new Error(`Unsupported PNG bit depth ${depth}: ${file}`);
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[color];
  if (!channels) throw new Error(`Unsupported PNG color type ${color}`);
  const raw = zlib.inflateSync(Buffer.concat(compressed));
  const stride = Math.ceil(width * channels * depth / 8);
  const bytesPerPixel = Math.max(1, Math.ceil(channels * depth / 8));
  const pixels = Buffer.alloc(height * stride);
  function paeth(a, b, c) {
    const p = a + b - c, pa = Math.abs(p-a), pb = Math.abs(p-b), pc = Math.abs(p-c);
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
  }
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    for (let x = 0; x < stride; x++) {
      const left = x >= bytesPerPixel ? pixels[y*stride+x-bytesPerPixel] : 0;
      const up = y ? pixels[(y-1)*stride+x] : 0;
      const upperLeft = y && x >= bytesPerPixel ? pixels[(y-1)*stride+x-bytesPerPixel] : 0;
      const predictor = [0, left, up, Math.floor((left+up)/2), paeth(left,up,upperLeft)][filter];
      if (predictor === undefined) throw new Error(`Unsupported PNG filter ${filter}`);
      pixels[y*stride+x] = (raw[y*(stride+1)+x+1]+predictor)&255;
    }
  }
  function opacity(x, y) {
    const pos = y*stride+x*channels;
    if (depth < 8) {
      const sample = (pixels[y*stride+Math.floor(x*depth/8)] >> (8-depth-(x*depth)%8)) & ((1<<depth)-1);
      if (color === 3) return alpha && sample < alpha.length ? alpha[sample] : 255;
      return alpha && sample === alpha.readUInt16BE(0) ? 0 : 255;
    }
    if (color === 6) return pixels[pos+3];
    if (color === 4) return pixels[pos+1];
    if (color === 3) return alpha && pixels[pos] < alpha.length ? alpha[pixels[pos]] : 255;
    if (color === 0 && alpha && pixels[pos] === alpha.readUInt16BE(0)) return 0;
    if (color === 2 && alpha && pixels[pos] === alpha.readUInt16BE(0) && pixels[pos+1] === alpha.readUInt16BE(2) && pixels[pos+2] === alpha.readUInt16BE(4)) return 0;
    return 255;
  }
  return { width, height, opacity, bytes };
}

function inherited(id, phase, cache) {
  if (cache.has(id)) return cache.get(id);
  const source = JSON.parse(fs.readFileSync(asset(id, 'models', 'json', phase), 'utf8'));
  const parent = source.parent && source.parent !== 'builtin/generated' ? inherited(source.parent.includes(':') ? source.parent : 'minecraft:' + source.parent, phase, cache) : {};
  const result = { ...parent, ...source, textures: { ...parent.textures, ...source.textures } };
  cache.set(id, result);
  return result;
}
function textureId(reference, textures) {
  const visited = new Set();
  while (reference.startsWith('#')) {
    if (visited.has(reference)) throw new Error(`Texture cycle ${reference}`);
    visited.add(reference);
    reference = textures[reference.slice(1)];
    if (typeof reference !== 'string') throw new Error('Unresolved face texture');
  }
  return reference.includes(':') ? reference : 'minecraft:' + reference;
}
function defaultUV(element, face) {
  const f = element.from, t = element.to;
  return {
    down: [f[0],16-t[2],t[0],16-f[2]], up: [f[0],f[2],t[0],t[2]],
    north: [16-t[0],16-t[1],16-f[0],16-f[1]], south: [f[0],16-t[1],t[0],16-f[1]],
    west: [f[2],16-t[1],t[2],16-f[1]], east: [16-t[2],16-t[1],16-f[2],16-f[1]]
  }[face];
}
function mapPoint(element, face, s, t) {
  const f = element.from, to = element.to;
  const at = (axis, fraction) => f[axis] + (to[axis]-f[axis])*fraction;
  return {
    north: [at(0,1-s),at(1,1-t),f[2]], south: [at(0,s),at(1,1-t),to[2]],
    west: [f[0],at(1,1-t),at(2,s)], east: [to[0],at(1,1-t),at(2,1-s)],
    up: [at(0,s),to[1],at(2,t)], down: [at(0,s),f[1],at(2,1-t)]
  }[face];
}
function rectangles(image, uv, frame) {
  const scale = image.width/16;
  const lowU = Math.min(uv[0],uv[2]), highU = Math.max(uv[0],uv[2]);
  const lowV = Math.min(uv[1],uv[3]), highV = Math.max(uv[1],uv[3]);
  if (lowU < -1e-8 || lowV < -1e-8 || highU > 16+1e-8 || highV > 16+1e-8) throw new Error(`UV outside sprite: ${uv}`);
  const rows = [];
  for (let y = Math.floor(lowV*scale); y < Math.ceil(highV*scale-1e-8); y++) {
    let start = null;
    for (let x = Math.floor(lowU*scale); x <= Math.ceil(highU*scale-1e-8); x++) {
      const visible = x < Math.ceil(highU*scale-1e-8) && image.opacity(x, y+frame*image.width) >= 128;
      if (visible && start === null) start = x;
      if (!visible && start !== null) {
        rows.push([Math.max(lowU,start/scale),Math.max(lowV,y/scale),Math.min(highU,x/scale),Math.min(highV,(y+1)/scale)]);
        start = null;
      }
    }
  }
  const merged = [];
  for (const row of rows) {
    const previous = merged.find(rect => rect[0] === row[0] && rect[2] === row[2] && Math.abs(rect[3]-row[1]) < 1e-8);
    if (previous) previous[3] = row[3]; else merged.push(row);
  }
  return merged;
}
function cropped(element, side, face, rect, uv) {
  const u = uv[2] < uv[0] ? [rect[2],rect[0]] : [rect[0],rect[2]];
  const v = uv[3] < uv[1] ? [rect[3],rect[1]] : [rect[1],rect[3]];
  const s = u.map(value => (value-uv[0])/(uv[2]-uv[0]));
  const t = v.map(value => (value-uv[1])/(uv[3]-uv[1]));
  if (face.rotation) throw new Error('Rotated UVs need explicit handling');
  const corners = [mapPoint(element,side,s[0],t[0]),mapPoint(element,side,s[1],t[1])];
  const result = clone(element);
  result.from = [0,1,2].map(axis => Math.min(...corners.map(point => point[axis])));
  result.to = [0,1,2].map(axis => Math.max(...corners.map(point => point[axis])));
  result.faces = { [side]: { ...clone(face), uv: [u[0],v[0],u[1],v[1]] } };
  return result;
}

function generate() {
const models = walk(path.join(pack, 'assets/minecraft/models')).filter(file => file.endsWith('.json'));
const manifest = { variants: [], textureRules: [], models: [], sourceHash: {} };
const animationCopies = new Map();
for (const phase of phases) {
  const cache = new Map(), images = new Map();
  let changedCount = 0, clippedFaces = 0;
  for (const file of models) {
    const relative = path.relative(pack,file).replaceAll('\\','/');
    if (!enabled(relative,phase.id)) continue;
    const id = 'minecraft:' + relative.replace(/^assets\/minecraft\/models\//,'').replace(/\.json$/,'');
    const original = JSON.parse(fs.readFileSync(file,'utf8'));
    const resolved = inherited(id,phase,cache);
    if (!resolved.elements || !resolved.elements.length) continue;
    // Abstract parent templates receive missing texture slots from children.
    // Bake their fully resolved children rather than the template itself.
    try {
      for (const element of resolved.elements) for (const face of Object.values(element.faces)) textureId(face.texture,resolved.textures);
    } catch { continue; }
    const elements = [];
    let changed = false;
    const textureOverrides = {};
    for (const element of resolved.elements) {
      const untouched = {};
      for (const [side,face] of Object.entries(element.faces)) {
        let sprite;
        try { sprite = textureId(face.texture,resolved.textures); }
        catch (error) { throw new Error(`${relative}: ${face.texture}: ${error.message}`); }
        if (!images.has(sprite)) images.set(sprite,png(asset(sprite,'textures','png',phase)));
        const image = images.get(sprite);
        const uv = face.uv || defaultUV(element,side);
        const metaPath = asset(sprite,'textures','png',phase)+'.mcmeta';
        const meta = fs.existsSync(metaPath) ? JSON.parse(fs.readFileSync(metaPath,'utf8')) : {};
        const animated = Boolean(meta.animation) && image.height > image.width;
        const first = meta.animation?.frames?.[0] ?? 0;
        const frame = typeof first === 'number' ? first : first.index;
        const rects = rectangles(image,uv,animated ? frame : 0);
        const area = rects.reduce((sum,r) => sum+(r[2]-r[0])*(r[3]-r[1]),0);
        const fullArea = Math.abs((uv[2]-uv[0])*(uv[3]-uv[1]));
        if (!animated && Math.abs(area-fullArea) < 1e-8) { untouched[side] = clone(face); continue; }
        if (fullArea === 0) throw new Error(`Zero UV area in ${relative}`);
        changed = true;
        clippedFaces++;
        const cutFace = clone(face);
        if (animated) {
          // Reuse the original PNG bytes, but freeze a dedicated decoration
          // sprite. Geometry cannot animate with the texture's silhouette.
          const hash = digest(image.bytes).slice(0,12);
          const name = `minecraft:block/better_moss_legacy/${sprite.split('/').pop()}_${hash}`;
          const key = `legacy_${hash}`;
          textureOverrides[key] = name;
          cutFace.texture = '#' + key;
          const targetRelative = `assets/minecraft/textures/block/better_moss_legacy/${sprite.split('/').pop()}_${hash}.png`;
          const target = path.join(pack,targetRelative);
          fs.mkdirSync(path.dirname(target),{recursive:true});
          fs.writeFileSync(target,image.bytes);
          fs.writeFileSync(target+'.mcmeta',JSON.stringify({animation:{frames:[frame]}})+'\n');
          animationCopies.set(targetRelative,true);
        }
        for (const rect of rects) elements.push(cropped(element,side,cutFace,rect,uv));
      }
      if (Object.keys(untouched).length) elements.push({...clone(element),faces:untouched});
    }
    if (!changed) continue;
    const output = { ...clone(original), textures: { ...resolved.textures,...textureOverrides }, elements };
    const sourcePath = `variants/legacy-solid/${phase.id}/${relative}`;
    const target = path.join(pack,sourcePath);
    fs.mkdirSync(path.dirname(target),{recursive:true});
    fs.writeFileSync(target,jsonText(output));
    manifest.variants.push({Path:relative,SourcePath:sourcePath,MinVersion:phase.id,BeforeVersion:phase.before});
    manifest.models.push({sourcePath,phase:phase.id,vanilla:phase.vanilla,original:relative});
    manifest.sourceHash[relative] = digest(fs.readFileSync(file));
    changedCount++;
  }
  console.log(`${phase.id}–before ${phase.before}: ${changedCount} models, ${clippedFaces} faces clipped to visible pixels.`);
}
for (const relative of animationCopies.keys()) {
  manifest.textureRules.push({Path:relative,BeforeVersion:'26.1'},{Path:relative+'.mcmeta',BeforeVersion:'26.1'});
}
// Merge identical adjacent version ranges so static decorations share files.
const grouped = new Map();
for (const variant of manifest.variants) {
  if (!grouped.has(variant.Path)) grouped.set(variant.Path,[]);
  grouped.get(variant.Path).push(variant);
}
const merged = [];
for (const entries of grouped.values()) {
  let previous;
  for (const entry of entries) {
    const bytes = fs.readFileSync(path.join(pack,entry.SourcePath));
    if (previous && previous.BeforeVersion === entry.MinVersion &&
        bytes.equals(fs.readFileSync(path.join(pack,previous.SourcePath)))) {
      previous.BeforeVersion = entry.BeforeVersion;
    } else {
      previous = {...entry};
      merged.push(previous);
    }
  }
}
manifest.variants = merged;
fs.writeFileSync(path.join(root,'cache/transparency/generated.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(`Generated ${manifest.variants.length} legacy variants; canonical models and texture bytes preserved.`);
}

function check() {
  const manifest = JSON.parse(fs.readFileSync(path.join(root,'cache/transparency/generated.json'),'utf8'));
  const images = new Map();
  let faces = 0;
  for (const [relative,hash] of Object.entries(manifest.sourceHash)) {
    if (digest(fs.readFileSync(path.join(pack,relative))) !== hash) throw new Error(`Canonical model changed: ${relative}; regenerate compatibility models.`);
  }
  for (const record of manifest.models) {
    const phase = phases.find(entry => entry.id === record.phase);
    const model = JSON.parse(fs.readFileSync(path.join(pack,record.sourcePath),'utf8'));
    const id = 'minecraft:' + record.original.replace(/^assets\/minecraft\/models\//,'').replace(/\.json$/,'');
    const original = inherited(id,phase,new Map());
    const opaqueOriginal = original.elements.filter(element =>
      element.from.every((value,axis) => element.to[axis] > value) &&
      Object.values(element.faces).every(face => {
        const sprite = textureId(face.texture,original.textures);
        const file = asset(sprite,'textures','png',phase);
        if (!images.has(file)) images.set(file,png(file));
        const image = images.get(file);
        for (let y=0;y<image.height;y++) for (let x=0;x<image.width;x++) if (image.opacity(x,y)<128) return false;
        return true;
      }));
    for (const solid of opaqueOriginal) {
      if (!model.elements.some(element => JSON.stringify(element.from) === JSON.stringify(solid.from) &&
          JSON.stringify(element.to) === JSON.stringify(solid.to) && JSON.stringify(element.faces) === JSON.stringify(solid.faces))) {
        throw new Error(`Opaque base geometry changed: ${record.sourcePath}`);
      }
    }
    for (const element of model.elements) {
      for (const [side,face] of Object.entries(element.faces)) {
        const sprite = textureId(face.texture,model.textures);
        const file = asset(sprite,'textures','png',phase);
        if (!images.has(file)) images.set(file,png(file));
        const image = images.get(file);
        const uv = face.uv || defaultUV(element,side);
        const lowX=Math.min(uv[0],uv[2])*image.width/16, highX=Math.max(uv[0],uv[2])*image.width/16;
        const lowY=Math.min(uv[1],uv[3])*image.width/16, highY=Math.max(uv[1],uv[3])*image.width/16;
        let frame=0;
        if (fs.existsSync(file+'.mcmeta')) {
          const meta=JSON.parse(fs.readFileSync(file+'.mcmeta','utf8'));
          const first=meta.animation?.frames?.[0] || 0;
          frame=typeof first==='number'?first:first.index;
        }
        for (let y=Math.floor(lowY+1e-8);y<Math.ceil(highY-1e-8);y++) {
          for (let x=Math.floor(lowX+1e-8);x<Math.ceil(highX-1e-8);x++) {
            if (image.opacity(x,y+frame*image.width)<128) throw new Error(`Transparent pixel on legacy face: ${record.sourcePath} ${side}`);
          }
        }
        if (face.texture === '#seam_growth' || face.texture.startsWith('#legacy_')) {
          const axes = ['north','south'].includes(side)?[0,1]:['east','west'].includes(side)?[2,1]:[0,2];
          for (let i=0;i<2;i++) {
            if (Math.abs((element.to[axes[i]]-element.from[axes[i]])-Math.abs(uv[i+2]-uv[i]))>0.01) throw new Error(`Pixel scale changed in ${record.sourcePath}`);
          }
        }
        faces++;
      }
    }
  }
  console.log(`Validated ${manifest.models.length} models and ${faces} opaque legacy faces; base geometry and canonical source hashes preserved.`);
}

module.exports = { png, rectangles, cropped, mapPoint, defaultUV };
if (require.main === module) {
  if (!config.versions.length) throw new Error('Prepare the official vanilla assets and cache/transparency/config.json first.');
  if (process.argv.includes('--check')) check(); else generate();
}
