// Safe, model-based adaptation of a local modpack. No registry-name catalogue,
// texture extraction or third-party geometry is needed.
const fs = require('node:fs');
const path = require('node:path');
const { species } = require('./update-bushy-leaves-enhanced.cjs');
const id = value => value.includes(':') ? value : `minecraft:${value}`;
const vanillaLeaves = new Set(['minecraft:block/leaves', ...Object.keys(species).map(s => `minecraft:block/${s}_leaves`)]);
const safeKeys = new Set(['parent', 'textures', 'ambientocclusion', 'gui_light', 'display', 'render_type', 'elements']);
const allDirections = ['down', 'up', 'north', 'south', 'west', 'east'];

function modelReferences(state) {
  const result = new Set();
  const visit = value => {
    if (!value || typeof value !== 'object') return;
    if (typeof value.model === 'string') result.add(id(value.model));
    for (const child of Object.values(value)) if (child && typeof child === 'object') visit(child);
  };
  visit(state);
  return result;
}

function adapt(models, modelId) {
  const chain = [], seen = new Set();
  let current = modelId, terminal;
  while (current) {
    if (seen.has(current)) return { status: 'skipped', reason: 'Cyclic model inheritance' };
    seen.add(current);
    if (vanillaLeaves.has(current)) { terminal = 'automatic'; break; }
    if (current === 'minecraft:block/cube_all') { terminal = 'cube'; break; }
    if (current === 'minecraft:block/block' || current === 'minecraft:block/cube') { terminal = 'geometry'; break; }
    const model = models[current];
    if (!model) return { status: 'skipped', reason: `Unresolved parent ${current}` };
    if (Object.keys(model).some(key => !safeKeys.has(key))) return { status: 'skipped', reason: 'Custom loader, extension or unsupported model property' };
    chain.push(model);
    current = model.parent ? id(model.parent) : null;
  }
  // Children override parent elements; an explicitly empty array is meaningful.
  const owner = chain.find(model => Object.hasOwn(model, 'elements'));
  if (terminal === 'automatic' && !owner) return { status: 'automatic' };
  let texture = '#all', tint = false;
  if (owner) {
    const elements = owner.elements;
    if (!Array.isArray(elements) || elements.length !== 1) return { status: 'skipped', reason: 'Non-cube geometry (fruit, overlays or special shape)' };
    const e = elements[0];
    if (JSON.stringify(e.from) !== '[0,0,0]' || JSON.stringify(e.to) !== '[16,16,16]' ||
      Object.keys(e).some(k => !['from', 'to', 'faces'].includes(k)) ||
      !e.faces || Object.keys(e.faces).length !== 6 || !allDirections.every(d => e.faces[d])) {
      return { status: 'skipped', reason: 'Nonstandard cube geometry or lighting' };
    }
    const faces = allDirections.map(d => e.faces[d]);
    const first = faces[0];
    if (faces.some((f, i) => f.texture !== first.texture || (f.tintindex ?? -1) !== (first.tintindex ?? -1) ||
      (f.tintindex !== undefined && ![-1, 0].includes(f.tintindex)) ||
      !f.uv || JSON.stringify(f.uv) !== '[0,0,16,16]' || f.cullface !== allDirections[i] ||
      Object.keys(f).some(k => !['texture', 'uv', 'cullface', 'tintindex'].includes(k)))) {
      return { status: 'skipped', reason: 'Multiple face textures, UVs, tint channels or face extensions' };
    }
    texture = first.texture;
    tint = first.tintindex === 0;
  } else if (terminal !== 'cube') return { status: 'skipped', reason: 'Not an ordinary full cube' };
  const textures = Object.assign({}, ...chain.toReversed().map(m => m.textures || {}));
  const aliases = new Set();
  while (texture?.startsWith('#')) {
    if (aliases.has(texture)) return { status: 'skipped', reason: 'Cyclic texture aliases' };
    aliases.add(texture);
    texture = textures[texture.slice(1)];
  }
  if (typeof texture !== 'string' || !/^(?:[a-z0-9_.-]+:)?[a-z0-9_./-]+$/.test(texture) || texture.split('/').includes('..')) {
    return { status: 'skipped', reason: 'Unresolved texture or unsupported material format' };
  }
  // Inherit non-geometric settings such as render_type from the original chain.
  // Only the new geometry reference and original material locations are emitted.
  const flattened = Object.assign({}, ...chain.toReversed());
  delete flattened.elements;
  flattened.parent = `bushy_leaves_enhanced:block/broad_0${tint ? '' : '_untinted'}`;
  flattened.textures = { ...textures, all: id(texture), particle: textures.particle || id(texture) };
  return { status: 'adapted', model: flattened };
}

function scan(data) {
  const candidates = new Set(), overrides = {}, report = [];
  const protectedModels = new Set();
  const protectChain = modelId => {
    const seen = new Set();
    while (modelId && !seen.has(modelId)) {
      seen.add(modelId);
      protectedModels.add(modelId);
      const parent = data.models[modelId]?.parent;
      modelId = parent ? id(parent) : null;
    }
  };
  const leafBlocks = new Set();
  const visitTag = (tagId, seen = new Set()) => {
    if (seen.has(tagId)) return;
    seen.add(tagId);
    for (const entry of data.tags?.[tagId]?.values || []) {
      const value = typeof entry === 'string' ? entry : entry.id;
      if (typeof value !== 'string') continue;
      if (value.startsWith('#')) visitTag(id(value.slice(1)), seen);
      else leafBlocks.add(id(value));
    }
  };
  visitTag('minecraft:leaves');
  for (const [blockId, state] of Object.entries(data.blockstates)) {
    if (blockId.startsWith('minecraft:')) continue;
    const leaf = leafBlocks.has(blockId) || /(?:^|\/)(?:[a-z0-9_]+_)?leaves$/.test(blockId.split(':')[1]);
    for (const model of modelReferences(state)) {
      if (leaf) candidates.add(model);
      // Preserve multipart layers and any models also used by non-leaf blocks.
      if (!leaf || state.multipart) protectChain(model);
    }
  }
  for (const modelId of [...candidates].sort()) {
    const result = adapt(data.models, modelId);
    if (result.status === 'adapted' && protectedModels.has(modelId)) {
      report.push({ model: modelId, status: 'skipped', reason: 'Multipart layer or model shared with a non-leaf block' });
      continue;
    }
    // Never override Minecraft or another pack's shared templates based on a
    // modded block referring to them. Automatic inheritance is enough there.
    if (result.status === 'adapted' && modelId.startsWith('minecraft:')) {
      report.push({ model: modelId, status: 'skipped', reason: 'Shared Minecraft model' });
      continue;
    }
    if (result.model) overrides[modelId] = result.model;
    report.push({ model: modelId, status: result.status, ...(result.reason ? { reason: result.reason } : {}) });
  }
  return { overrides, report };
}

if (require.main === module) {
  const [input, output] = process.argv.slice(2);
  if (!input || !output) throw Error('Usage: node bushy-leaves-enhanced-compatibility.cjs input.json new-output-directory');
  const data = JSON.parse(fs.readFileSync(input, 'utf8').replace(/^\uFEFF/, ''));
  const { overrides, report } = scan(data);
  if (fs.existsSync(output)) throw Error('Output directory already exists');
  fs.mkdirSync(output, { recursive: true });
  for (const [modelId, model] of Object.entries(overrides)) {
    if (!/^[a-z0-9_.-]+:[a-z0-9_./-]+$/.test(modelId) || modelId.includes('..')) throw Error(`Unsafe model ID: ${modelId}`);
    const [namespace, relative] = modelId.split(':');
    const destination = path.join(output, 'assets', namespace, 'models', relative + '.json');
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, JSON.stringify(model, null, 2) + '\n');
  }
  fs.writeFileSync(path.join(output, 'scan-report.json'), JSON.stringify(report, null, 2) + '\n');
  const counts = {};
  for (const entry of report) counts[entry.status] = (counts[entry.status] || 0) + 1;
  console.log(JSON.stringify(counts));
}
module.exports = { adapt, scan, modelReferences };
