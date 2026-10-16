// Lighting-only fallback for clients before native element light_emission (1.21.2).
const fs = require('node:fs');
const path = require('node:path');
function updateOreLighting() {
  const root = path.resolve(__dirname, '../resource_packs/alternative_ores');
  const prefix = 'variants/legacy-lighting/';
  const read = relative => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
  const write = (relative, value) => {
    const destination = path.join(root, relative);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, JSON.stringify(value, null, 2) + '\n');
  };
  const rules = read('variants/ore-versions.json');
  rules.FileVariants = (rules.FileVariants || []).filter(rule => !rule.SourcePath.startsWith(prefix));
  rules.FileRules = rules.FileRules.filter(rule => !/^assets\/[^/]+\/models\/block\/alternative_ores\/legacy_lighting\//.test(rule.Path));
  const baseModels = {
    'occultism:block/alternative_ores/otherstone': { name: 'otherstone', namespace: 'occultism', gate: 'assets/occultism/models/block/alternative_ores/otherstone.json', minimum: '1.15.2', textures: { all: 'occultism:block/otherstone' } },
    'silentgear:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'silentgear', gate: 'assets/silentgear/models/block/alternative_ores/end_stone.json', minimum: '1.15.2', textures: { all: 'minecraft:block/end_stone' } },
    'minecraft:block/blackstone': { name: 'blackstone', namespace: 'silentgear', minimum: '1.19.2', textures: { end: 'minecraft:block/blackstone_top', side: 'minecraft:block/blackstone' } },
    'rftoolsbase:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'rftoolsbase', gate: 'assets/rftoolsbase/models/block/alternative_ores/end_stone.json', minimum: '1.14.3', textures: { all: 'minecraft:block/end_stone' } },
    'deeperdarker:block/alternative_ores/sculk_stone': { name: 'sculk_stone', namespace: 'deeperdarker', gate: 'assets/deeperdarker/models/block/alternative_ores/sculk_stone.json', minimum: '1.19', textures: { all: 'deeperdarker:block/sculk_stone' } },
    'deeperdarker:block/alternative_ores/gloomslate': { name: 'gloomslate', namespace: 'deeperdarker', gate: 'assets/deeperdarker/models/block/alternative_ores/gloomslate.json', minimum: '1.19', textures: { all: 'deeperdarker:block/gloomslate' } },
    'undergarden:block/alternative_ores/depthrock': { name: 'depthrock', namespace: 'undergarden', gate: 'assets/undergarden/models/block/alternative_ores/depthrock.json', minimum: '1.16.1', textures: { all: 'undergarden:block/depthrock' } },
    'undergarden:block/alternative_ores/shiverstone': { name: 'shiverstone', namespace: 'undergarden', gate: 'assets/undergarden/models/block/alternative_ores/shiverstone.json', minimum: '1.16.1', textures: { all: 'undergarden:block/shiverstone' } },
    'undergarden:block/alternative_ores/tremblecrust': { name: 'tremblecrust', namespace: 'undergarden', gate: 'assets/undergarden/models/block/alternative_ores/tremblecrust.json', minimum: '1.16.1', textures: { all: 'undergarden:block/tremblecrust' } },
    'undergarden:block/alternative_ores/dreadrock': { name: 'dreadrock', namespace: 'undergarden', gate: 'assets/undergarden/models/block/alternative_ores/dreadrock.json', minimum: '1.16.1', textures: { all: 'undergarden:block/dreadrock' } },
    'oritech:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'oritech', gate: 'assets/oritech/models/block/alternative_ores/end_stone.json', minimum: '1.20.4', textures: { all: 'minecraft:block/end_stone' } },
    'silentgems:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'silentgems', gate: 'assets/silentgems/models/block/alternative_ores/end_stone.json', minimum: '1.13.2', textures: { all: 'minecraft:block/end_stone' } },
    'bigreactors:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'bigreactors', gate: 'assets/bigreactors/models/block/alternative_ores/end_stone.json', minimum: '1.16.3', textures: { all: 'minecraft:block/end_stone' } },
    'aether:block/alternative_ores/holystone': { name: 'holystone', namespace: 'aether', gate: 'assets/aether/models/block/alternative_ores/holystone.json', minimum: '1.19.2', textures: { all: 'aether:block/natural/holystone' } },
    'neovitae:block/alternative_ores/dungeon_stone': { name: 'dungeon_stone', namespace: 'neovitae', gate: 'assets/neovitae/models/block/alternative_ores/dungeon_stone.json', minimum: '1.21.1', textures: { all: 'neovitae:block/dungeon/dungeon_stone' } },
    'astralsorcery:block/alternative_ores/sand': { name: 'sand', namespace: 'astralsorcery', gate: 'assets/astralsorcery/models/block/alternative_ores/sand.json', minimum: '1.15.2', textures: { all: 'minecraft:block/sand' } },
    'ad_astra:block/alternative_ores/moon_stone': { name: 'moon_stone', namespace: 'ad_astra', gate: 'assets/ad_astra/models/block/alternative_ores/moon_stone.json', minimum: '1.18.2', textures: { all: 'ad_astra:block/moon_stone' } },
    'ad_astra:block/alternative_ores/mars_stone': { name: 'mars_stone', namespace: 'ad_astra', gate: 'assets/ad_astra/models/block/alternative_ores/mars_stone.json', minimum: '1.18.2', textures: { all: 'ad_astra:block/mars_stone' } },
    'ad_astra:block/alternative_ores/mercury_stone': { name: 'mercury_stone', namespace: 'ad_astra', gate: 'assets/ad_astra/models/block/alternative_ores/mercury_stone.json', minimum: '1.18.2', textures: { all: 'ad_astra:block/mercury_stone' } },
    'ad_astra:block/alternative_ores/venus_stone': { name: 'venus_stone', namespace: 'ad_astra', gate: 'assets/ad_astra/models/block/alternative_ores/venus_stone.json', minimum: '1.18.2', textures: { all: 'ad_astra:block/venus_stone' } },
    'ad_astra:block/alternative_ores/glacio_stone': { name: 'glacio_stone', namespace: 'ad_astra', gate: 'assets/ad_astra/models/block/alternative_ores/glacio_stone.json', minimum: '1.18.2', textures: { all: 'ad_astra:block/glacio_stone' } },
    'eternal_starlight:block/alternative_ores/packed_nightfall_mud': { name: 'packed_nightfall_mud', namespace: 'eternal_starlight', gate: 'assets/eternal_starlight/models/block/alternative_ores/packed_nightfall_mud.json', minimum: '1.21', textures: { all: 'eternal_starlight:block/packed_nightfall_mud' } },
    'eternal_starlight:block/alternative_ores/nightfall_mud': { name: 'nightfall_mud', namespace: 'eternal_starlight', gate: 'assets/eternal_starlight/models/block/alternative_ores/nightfall_mud.json', minimum: '1.21', textures: { all: 'eternal_starlight:block/nightfall_mud' } },
    'eternal_starlight:block/alternative_ores/eternal_ice': { name: 'eternal_ice', namespace: 'eternal_starlight', gate: 'assets/eternal_starlight/models/block/alternative_ores/eternal_ice.json', minimum: '1.21', textures: { all: 'eternal_starlight:block/eternal_ice' } },
    'eternal_starlight:block/alternative_ores/haze_ice': { name: 'haze_ice', namespace: 'eternal_starlight', gate: 'assets/eternal_starlight/models/block/alternative_ores/haze_ice.json', minimum: '1.21', textures: { all: 'eternal_starlight:block/haze_ice' } },
    'eternal_starlight:block/alternative_ores/grimstone': { name: 'grimstone', namespace: 'eternal_starlight', gate: 'assets/eternal_starlight/models/block/alternative_ores/grimstone.json', minimum: '1.21', textures: { all: 'eternal_starlight:block/grimstone' } },
    'eternal_starlight:block/alternative_ores/voidstone': { name: 'voidstone', namespace: 'eternal_starlight', gate: 'assets/eternal_starlight/models/block/alternative_ores/voidstone.json', minimum: '1.21', textures: { all: 'eternal_starlight:block/voidstone' } },
    'minecraft:block/stone': { name: 'stone', minimum: '1.13', textures: { all: 'minecraft:block/stone' } },
    'minecraft:block/deepslate': { name: 'deepslate', minimum: '1.17', textures: { end: 'minecraft:block/deepslate_top', side: 'minecraft:block/deepslate' } },
    'minecraft:block/netherrack': { name: 'netherrack', minimum: '1.13', textures: { all: 'minecraft:block/netherrack' } },
    'minecraft:block/end_stone': { name: 'end_stone', namespace: 'alltheores', minimum: '1.16.2', textures: { all: 'minecraft:block/end_stone' } },
    'alltheores:block/alternative_ores/otherstone': { name: 'otherstone', namespace: 'alltheores', gate: 'assets/alltheores/models/block/alternative_ores/otherstone.json', minimum: '1.16.2', textures: { all: 'alltheores:block/alternative_ores/otherstone' } },
    'allthemodium:block/alternative_ores/otherstone': { name: 'otherstone', namespace: 'allthemodium', gate: 'assets/allthemodium/models/block/alternative_ores/otherstone.json', minimum: '1.15.2', textures: { all: 'allthemodium:block/alternative_ores/otherstone' } },
    'allthemodium:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'allthemodium', gate: 'assets/allthemodium/models/block/alternative_ores/end_stone.json', minimum: '1.15.2', textures: { all: 'minecraft:block/end_stone' } },
    'draconicevolution:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'draconicevolution', gate: 'assets/draconicevolution/models/block/alternative_ores/end_stone.json', minimum: '1.16.5', textures: { all: 'minecraft:block/end_stone' } },
    'mysticalagriculture:block/alternative_ores/soulstone': { name: 'soulstone', namespace: 'mysticalagriculture', gate: 'assets/mysticalagriculture/models/block/alternative_ores/soulstone.json', minimum: '1.14.4', textures: { all: 'mysticalagriculture:block/soulstone' } },
    'mysticalagradditions:block/alternative_ores/end_stone': { name: 'end_stone', namespace: 'mysticalagradditions', gate: 'assets/mysticalagradditions/models/block/alternative_ores/end_stone.json', minimum: '1.16.4', textures: { all: 'minecraft:block/end_stone' } },
    'forbidden_arcanus:block/alternative_ores/dark_stone': { name: 'dark_stone', namespace: 'forbidden_arcanus', gate: 'assets/forbidden_arcanus/models/block/alternative_ores/dark_stone.json', minimum: '1.13.2', textures: { all: 'forbidden_arcanus:block/darkstone' } },
    'forbidden_arcanus:block/alternative_ores/darkstone': { name: 'darkstone', namespace: 'forbidden_arcanus', gate: 'assets/forbidden_arcanus/models/block/alternative_ores/darkstone.json', minimum: '1.17.1', textures: { all: 'forbidden_arcanus:block/darkstone' } },
    'xycraft_world:block/alternative_ores/kivi': { name: 'kivi', namespace: 'xycraft_world', gate: 'assets/xycraft_world/models/block/alternative_ores/kivi.json', minimum: '1.19.2', textures: { all: 'xycraft_world:block/kivi' } },
    'minecraft:block/alternative_ores/ancient_debris_base': { name: 'ancient_debris', minimum: '1.16', textures: { end: 'minecraft:block/ancient_debris_top', side: 'minecraft:block/ancient_debris_side' } }
  };
  for (const [parent, base] of Object.entries(baseModels)) {
    if (base.namespace && !fs.existsSync(path.join(root, `assets/${base.namespace}`))) continue;
    const namespace = base.namespace || 'minecraft';
    base.model = `${namespace}:block/alternative_ores/legacy_lighting/${base.name}`;
    const relative = `assets/${namespace}/models/block/alternative_ores/legacy_lighting/${base.name}.json`;
    // Older BlockModel.hasAmbientOcclusion() ALWAYS delegates to a parent.
    // A child override is ineffective there, so keep these core models parentless.
    // These are the same six faces as vanilla cube_all/cube_column, with their
    // original texture orientation and default UVs; no crystal geometry is added.
    const faces = {};
    for (const direction of ['down', 'up', 'north', 'south', 'west', 'east']) {
      const texture = base.textures.all ? '#all' : (direction === 'down' || direction === 'up' ? '#end' : '#side');
      faces[direction] = { texture, cullface: direction };
    }
    write(relative, {
      ambientocclusion: false,
      textures: { ...base.textures, particle: base.textures.all ? '#all' : '#side' },
      elements: [{ from: [0, 0, 0], to: [16, 16, 16], faces }]
    });
    const versionOptions = base.gate ? { Versions: rules.FileRules.find(rule => rule.Path === base.gate).Versions } : { MinVersion: base.minimum };
    rules.FileRules.push({ Path: relative, ...versionOptions, BeforeVersion: '1.21.2' });
  }
  const variant = (relative, model) => {
    const source = prefix + relative;
    write(source, model);
    const route = { Path: relative, SourcePath: source, BeforeVersion: '1.21.2' };
    if (rules.FileVariants.some(rule => rule.Path === relative && rule.SourcePath.startsWith('variants/forbidden-old-darkstone/'))) route.MinVersion = '1.16.1';
    const oldGemHosts = new Set(rules.FileVariants.filter(rule => rule.Path === relative && rule.SourcePath.startsWith('variants/silentgems-old-hosts/')).flatMap(rule => rule.Versions || []));
    if (oldGemHosts.size) route.Versions = rules.FileRules.find(rule => rule.Path === relative).Versions.filter(version => !oldGemHosts.has(version));
    if (!route.Versions || route.Versions.length) rules.FileVariants.push(route);
  };
  for (const namespace of ['minecraft', 'mekanism', 'appliedenergistics2', 'ae2', 'create', 'alltheores', 'immersiveengineering', 'allthemodium', 'draconicevolution', 'ars_nouveau', 'mysticalagriculture', 'tconstruct', 'modern_industrialization', 'actuallyadditions', 'irons_spellbooks', 'mysticalagradditions', 'forbidden_arcanus', 'evilcraft', 'xycraft_world', 'theurgy', 'occultism', 'silentgear', 'rftoolsbase', 'deeperdarker', 'undergarden', 'oritech', 'silentgems', 'powah', 'bigreactors', 'aether', 'neovitae', 'astralsorcery', 'ad_astra', 'eternal_starlight']) {
    const directory = `assets/${namespace}/blockstates`;
    if (!fs.existsSync(path.join(root, directory))) continue;
    for (const name of fs.readdirSync(path.join(root, directory)).filter(name => name.endsWith('.json'))) {
      const relative = `${directory}/${name}`;
      const state = read(relative);
      const first = state.multipart?.[0]?.apply;
      if (!first || !baseModels[first.model]) throw Error(`Unexpected ore base in ${relative}`);
      // Old MultipartBakedModel copies AO from its FIRST component. An overlay-only
      // change would leave the entire ore using the stone model's smooth-light path.
      for (const part of state.multipart) {
        const apply = part.apply;
        if (apply && !Array.isArray(apply) && baseModels[apply.model]) apply.model = baseModels[apply.model].model;
      }
      variant(relative, state);
    }
    const layouts = `assets/${namespace}/models/block/alternative_ores`;
    for (const name of fs.readdirSync(path.join(root, layouts)).filter(name => /^(?:copper_)?crystal_layout_[1-6]_overlay\.json$/.test(name))) {
      const relative = `${layouts}/${name}`;
      const model = read(relative);
      // These overlays already contain their complete geometry. The block/block
      // parent supplies no geometry or textures, but overrides AO on old clients.
      if (model.parent !== 'minecraft:block/block') throw Error(`Unexpected overlay parent in ${relative}`);
      delete model.parent;
      model.ambientocclusion = false;
      variant(relative, model);
    }
  }
  fs.writeFileSync(path.join(root, 'variants/ore-versions.json'), '{\n' + Object.entries(rules).map(([name, entries]) =>
    `  ${JSON.stringify(name)}: [\n` + entries.map(entry => '    { ' + Object.entries(entry).map(([key, value]) =>
      `${JSON.stringify(key)}: ${JSON.stringify(value)}`).join(', ') + ' }').join(',\n') + '\n  ]'
  ).join(',\n') + '\n}\n');
  console.log(`Updated ${rules.FileVariants.filter(rule => rule.SourcePath.startsWith(prefix)).length} lighting-only variants for Minecraft before 1.21.2.`);
}
module.exports = updateOreLighting;
if (require.main === module) updateOreLighting();
