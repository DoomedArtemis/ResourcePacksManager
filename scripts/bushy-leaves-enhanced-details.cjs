// Original 16-pixel ornament artwork and flat model overlays.
// Editable pixel grids keep silhouettes and palette deliberate at Minecraft scale.
const zlib = require('node:zlib');
const accents = {
  spruce: { sprite: 'spruce_cone', rarity: 10, additional: [
    { suffix: 'growth', sprite: 'spruce_growth', rarity: 12, placements: ['side'] },
  ] },
  oak: { sprite: 'oak_acorns', rarity: 18, additional: [
    { suffix: 'apple', sprite: 'apple', rarity: 36 },
    { suffix: 'blossoms', sprite: 'oak_blossoms', rarity: 18, placements: ['top', 'side'] },
  ] },
  dark_oak: { sprite: 'apple', rarity: 24, additional: [
    { suffix: 'blossoms', sprite: 'oak_blossoms', rarity: 32, placements: ['top', 'side'] },
  ] },
  birch: { sprite: 'birch_catkins', rarity: 16 },
  jungle: { sprite: 'jungle_orchid', rarity: 24, additional: [
    { suffix: 'vine_short', sprite: 'jungle_vine_short', rarity: 18 },
    { suffix: 'vine_long', sprite: 'jungle_vine_long', rarity: 36 },
  ] },
  flowering_azalea: { sprite: 'azalea_blossom', rarity: 10, placements: ['top', 'side'] },
  cherry: { sprite: 'cherries', rarity: 18 },
};
const sprites = {
  cherries: {
    palette: { s: '657546', h: 'e18b82', r: 'ba3c4b', R: 'a62d43', d: '70273b' },
    rows: [
      '.......s........', '......s.s.......', '......s..s......',
      '.....s...s......', '....hrr..hrr....', '....rRd..rRd....',
      '.....dd...dd....', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  spruce_growth: {
    growth: true, tinted: true,
    palette: { s: '969b8a', m: 'c6cdb2', h: 'e5e9cf' },
    rows: [
      '.......h........', '......hmh.......', '.......m........',
      '......hmh.......', '.....hmsmh......', '.......s........',
      '.......s........', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  jungle_vine_short: {
    tinted: true, trailing: true,
    palette: { s: '858d7c', h: 'c4cdb6' },
    rows: [
      '.......s........', '......hs........', '.......s........',
      '.......sh.......', '.......s........', '......hs........',
      '......s.........', '......h.........', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  jungle_vine_long: {
    tinted: true, trailing: true,
    palette: { s: '858d7c', h: 'c4cdb6' },
    rows: [
      '.......s........', '.......sh.......', '.......s........',
      '......hs........', '......s.........', '......sh........',
      '......s.........', '.....hs.........', '......s.........',
      '......h.........', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  azalea_blossom: {
    growth: true,
    palette: { s: '506747', g: '759052', p: 'b977a7', h: 'deabc9', y: 'e0bf79' },
    rows: [
      '.......p........', '......hyh.......', '.......p........',
      '.......s........', '......gs........', '.......s........',
      '................', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  oak_blossoms: {
    surface: true,
    palette: { w: 'dcd9bc', p: 'd1b3b1', y: 'b9a568', b: 'bfa9a0' },
    rows: [
      '................', '................', '................',
      '.........b......', '.....w..........', '....wyw.........',
      '.....p..........', '................', '................',
      '...........p....', '..........pyw...', '...........w....',
      '................', '................', '................', '................',
    ],
  },
  apple: {
    palette: { s: '705236', g: '668541', d: '792b2b', r: 'b83c36', h: 'd65a49', H: 'e78b65' },
    rows: [
      '.......sg.......', '.....rr.rr......', '.....rHrrd......',
      '.....rhrdd......', '......rdd.......', '................',
      '................', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  spruce_cone: {
    palette: { s: '66513a', d: '493024', b: '75432d', m: '9b5937', h: 'be7c4a', H: 'd49a61' },
    rows: [
      '.......s........', '......dhmd......', '.....dhmbd......',
      '......mbd.......', '.......d........', '................',
      '................', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  oak_acorns: {
    palette: { s: '6c5b37', d: '4e3a23', c: '79603b', C: 'a18450', b: 'a57a3f', h: 'ceaa62', H: 'e0c17e' },
    rows: [
      '.......s........', '......s.s.......', '.....Cc..cC.....',
      '......h..h......', '......b..b......', '................',
      '................', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  birch_catkins: {
    palette: { s: '665e35', d: '756338', b: 'a28e4a', h: 'c1ad63', H: 'd3c580' },
    rows: [
      '.......s........', '......s.s.......', '.....bh..s......',
      '.....hb..bh.....', '.....db..hb.....', '.........db.....',
      '..........b.....', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
  jungle_orchid: {
    palette: { s: '3b6139', g: '63874b', d: '764c72', p: 'b782ac', h: 'd9b8ce', w: 'e8dcd9', y: 'c8a55a' },
    rows: [
      '.......s........', '......gs........', '.......s........',
      '.......w........', '......wyh.......', '.......p........',
      '................', '................', '................',
      '................', '................', '................',
      '................', '................', '................', '................',
    ],
  },
};

function spritePixels(name) {
  const { rows, palette } = sprites[name];
  const pixels = new Uint8Array(16 * 16 * 4);
  if (rows.length !== 16 || rows.some(row => row.length !== 16)) throw Error(`Invalid sprite grid: ${name}`);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const symbol = rows[y][x];
    if (symbol === '.') continue;
    const hex = palette[symbol];
    if (!hex) throw Error(`Missing sprite palette entry: ${name}/${symbol}`);
    const at = (y * 16 + x) * 4;
    for (let channel = 0; channel < 3; channel++) pixels[at + channel] = parseInt(hex.slice(channel * 2, channel * 2 + 2), 16);
    pixels[at + 3] = 255;
  }
  return { width: 16, pixels };
}

function spritePng(name) {
  const { pixels } = spritePixels(name);
  const crc = data => {
    let c = 0xffffffff;
    for (const byte of data) { c ^= byte; for (let bit = 0; bit < 8; bit++) c = (c >>> 1) ^ ((c & 1) ? 0xedb88320 : 0); }
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const prefix = Buffer.alloc(8), suffix = Buffer.alloc(4);
    prefix.writeUInt32BE(data.length); prefix.write(type, 4);
    suffix.writeUInt32BE(crc(Buffer.concat([Buffer.from(type), data])));
    return Buffer.concat([prefix, data, suffix]);
  };
  const header = Buffer.alloc(13); header.writeUInt32BE(16); header.writeUInt32BE(16, 4); header[8] = 8; header[9] = 6;
  const raw = Buffer.alloc(16 * 65);
  for (let row = 0; row < 16; row++) Buffer.from(pixels.subarray(row * 64, row * 64 + 64)).copy(raw, row * 65 + 1);
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

function accentTypes(species) {
  const accent = accents[species];
  return [accent, ...(accent.additional || [])].map(type => ({
    sprite: type.sprite, rarity: type.rarity, modelPrefix: species + (type.suffix ? `_${type.suffix}` : ''),
    placements: type.placements || ['underside', 'side'],
  }));
}

function detailModel(species, position, sprite = accents[species].sprite) {
  if (sprites[sprite].surface) {
    if (!['top', 'side'].includes(position)) throw Error('Unknown blossom placement');
    const top = position === 'top';
    const front = { texture: '#detail', uv: [0, 0, 16, 16], cullface: top ? 'up' : 'north' };
    const back = { ...front, uv: [16, 0, 0, 16] };
    return {
      parent: 'minecraft:block/block',
      textures: { detail: `bushy_leaves_enhanced:block/details/${sprite}`, particle: `minecraft:block/${species}_leaves` },
      elements: [{
        // Offset the flat overlay slightly so it cannot fight the core surface.
        from: top ? [0, 16.02, 0] : [0, 0, -0.02],
        to: top ? [16, 16.02, 16] : [16, 16, -0.02],
        faces: top ? { up: front, down: back } : { north: front, south: back },
      }],
    };
  }
  const growing = !!sprites[sprite].growth;
  const trailing = !!sprites[sprite].trailing;
  if (!(growing ? ['top', 'side'] : ['underside', 'side']).includes(position)) throw Error('Unknown detail placement');
  const side = position === 'side';
  const origin = side
    ? [8.5, 7, growing || trailing ? -1.5 : 0.25]
    : growing ? [4.5, 15.5, 3] : [5.5, trailing ? -2 : 0.75, 10];
  const [x, attachment, z] = origin;
  const cullface = side ? 'north' : growing ? 'up' : 'down';
  const rotation = side ? { origin, axis: 'x', angle: growing ? -45 : 22.5, rescale: false } : undefined;
  // Crop to the occupied pixel grid, then use exactly one model unit per texel.
  // Never squeeze a detailed 16x16 icon onto a four-unit ornament.
  const rows = sprites[sprite].rows;
  let left = 16, right = 0, bottom = 0;
  for (let row = 0; row < 16; row++) for (let column = 0; column < 16; column++) if (rows[row][column] !== '.') {
    left = Math.min(left, column); right = Math.max(right, column + 1); bottom = Math.max(bottom, row + 1);
  }
  const width = right - left, height = bottom;
  const top = growing ? attachment + height : attachment;
  const face = mirrored => ({ texture: '#detail', uv: mirrored ? [right, 0, left, bottom] : [left, 0, right, bottom], cullface,
    ...(sprites[sprite].tinted ? { tintindex: 0 } : {}),
  });
  return {
    parent: 'minecraft:block/block',
    textures: { detail: `bushy_leaves_enhanced:block/details/${sprite}`, particle: `minecraft:block/${species}_leaves` },
    elements: [
      { from: [x - width / 2, top - height, z], to: [x + width / 2, top, z], shade: false,
        ...(rotation ? { rotation } : {}), faces: { north: face(false), south: face(true) } },
      { from: [x, top - height, z - width / 2], to: [x, top, z + width / 2], shade: false,
        ...(rotation ? { rotation } : {}), faces: { west: face(false), east: face(true) } },
    ],
  };
}

function detailChoices(species) {
  const types = accentTypes(species);
  const gcd = (a, b) => b ? gcd(b, a % b) : a;
  const denominator = types.reduce((n, t) => n * t.rarity / gcd(n, t.rarity), 1);
  const variantFactor = types.reduce((n, t) => {
    const count = t.placements.length * 4;
    return n * count / gcd(n, count);
  }, 1);
  const decoratedWeight = types.reduce((n, t) => n + denominator / t.rarity, 0);
  if (decoratedWeight >= denominator) throw Error('Decorations must leave room for undecorated leaves');
  const choices = [{ model: 'bushy_leaves_enhanced:block/details/none', weight: (denominator - decoratedWeight) * variantFactor }];
  for (const type of types) for (const placement of type.placements) for (const y of [0, 90, 180, 270]) {
    choices.push({ model: `bushy_leaves_enhanced:block/details/${type.modelPrefix}_${placement}`, y, uvlock: false, weight: denominator / type.rarity * variantFactor / (type.placements.length * 4) });
  }
  return choices;
}

module.exports = { accents, accentTypes, sprites, spritePixels, spritePng, detailModel, detailChoices };
