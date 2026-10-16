const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { planSync, normalizeModrinth, normalizeCurseForge, zipEntries, applyEdits } = require('./sync-mod-compatibility.cjs');

function storedZip(files) {
  const locals = [], centrals = []; let offset = 0;
  for (const [name, content] of Object.entries(files)) {
    const bytes = Buffer.from(content), filename = Buffer.from(name), local = Buffer.alloc(30), central = Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50); local.writeUInt32LE(bytes.length, 18); local.writeUInt32LE(bytes.length, 22); local.writeUInt16LE(filename.length, 26);
    central.writeUInt32LE(0x02014b50); central.writeUInt32LE(bytes.length, 20); central.writeUInt32LE(bytes.length, 24); central.writeUInt16LE(filename.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(local, filename, bytes); centrals.push(central, filename); offset += local.length + filename.length + bytes.length;
  }
  const end = Buffer.alloc(22), directory = Buffer.concat(centrals);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(Object.keys(files).length, 8); end.writeUInt16LE(Object.keys(files).length, 10); end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, end]);
}
const namespace = 'create';
const states = 'assets/create/blockstates/zinc_ore.json', model = 'assets/create/models/block/zinc_ore.json';
const upstream = {
  [states]: '{"variants":{"":{"model":"create:block/zinc_ore"}}}',
  [model]: '{"parent":"minecraft:block/cube_all"}'
};
const jar = entries => zipEntries(storedZip(entries));
const file = (platform, project, version, id) => ({ platform, project, versions: [version], id, loaders: ['forge'], date: '2026-01-01T00:00:00Z' });

async function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'compatibility-sync-test-'));
  try {
    const packRoot = path.join(root, 'resource_packs/fixture');
    fs.mkdirSync(path.join(packRoot, 'assets/create/blockstates'), { recursive: true });
    fs.mkdirSync(path.join(packRoot, 'variants'), { recursive: true });
    fs.writeFileSync(path.join(packRoot, states), upstream[states]);
    const original = `# Preserve comments and metadata\r\n@{ Compatibility = @{ create = @{ Versions = @('1.21.1'); Support = 'Keep me' } }; Modrinth = @{ Dependencies = @(@{ ProjectId = 'Ab12Cd34'; Versions = @('1.21.1') }) }; CurseForge = @{ Dependencies = @(@{ ProjectId = '12345'; Versions = @('1.21.1') }) }; FileOptionsPath = 'variants/rules.json' }\r\n`;
    const configFile = path.join(packRoot, 'pack.build.psd1'); fs.writeFileSync(configFile, original);
    const locations = [...original.matchAll(/@\('1\.21\.1'\)/g)].map((match, index) => ({ kind: ['compatibility', 'modrinth', 'curseforge'][index], key: [namespace, 'Ab12Cd34', '12345'][index], start: match.index, end: match.index + match[0].length }));
    const rulesText = '{\n  "FileRules": [\n    { "Path": "assets/create/blockstates/zinc_ore.json", "Versions": ["1.21.1"] },\n    { "Path": "assets/create/models/block/copper_ore.json", "Versions": ["1.16.5"] }\n  ],\n  "FileVariants": []\n}\n';
    const rulesFile = path.join(packRoot, 'variants/rules.json'); fs.writeFileSync(rulesFile, rulesText);
    const options = { Compatibility: { create: { Versions: ['1.21.1'], Support: 'Keep me' } }, Modrinth: { Dependencies: [{ ProjectId: 'Ab12Cd34', Versions: ['1.21.1'] }] }, CurseForge: { Dependencies: [{ ProjectId: '12345', Versions: ['1.21.1'] }] }, FileOptionsPath: 'variants/rules.json' };
    const request = { root, versions: ['1.16.5', '1.21.1', '26.2'], packs: [{ name: 'fixture', root: packRoot, file: configFile, options, locations, groups: [{ namespaces: [namespace], projects: [{ modrinth: 'Ab12Cd34', curseforge: '12345' }] }] }] };
    let candidate = jar(upstream);
    const services = {
      sources: new Set(['fixture']),
      async catalogue(platform, project) { return [file(platform, project, '1.21.1', 'old'), ...(platform === 'curseforge' ? [file(platform, project, '26.2', 'new')] : [])]; },
      async jar(record) { return record.id === 'old' ? jar(upstream) : candidate; }
    };
    const plan = await planSync(request, services);
    assert.equal(plan.changes.length, 2);
    const updated = plan.changes.find(change => change.path === configFile).content;
    assert.ok(updated.includes("create = @{ Versions = @('1.21.1', '26.2')"));
    assert.ok(updated.includes("ProjectId = 'Ab12Cd34'; Versions = @('1.21.1')"), 'Modrinth must not inherit CurseForge-only versions');
    assert.ok(updated.includes("ProjectId = '12345'; Versions = @('1.21.1', '26.2')"));
    assert.ok(updated.startsWith('# Preserve comments and metadata\r\n'));
    assert.ok(updated.includes("Support = 'Keep me'"));
    const nextRules = JSON.parse(plan.changes.find(change => change.path === rulesFile).content);
    assert.deepEqual(nextRules.FileRules[0].Versions, ['1.21.1', '26.2']);
    assert.deepEqual(nextRules.FileRules[1].Versions, ['1.16.5'], 'Historical copper rules must not follow new zinc support');
    assert.equal(fs.readFileSync(configFile, 'utf8'), original, 'Planning/checking must not modify configuration');
    assert.equal(plan.report.inspections.find(item => item.file === 'new').referenceVersion, '1.21.1');

    candidate = jar({ [states]: '{"variants":{"new_property=true":{"model":"create:block/zinc_ore"}}}' });
    const changed = await planSync(request, services);
    assert.equal(changed.changes.length, 0);
    assert.equal(changed.report.needsReview.length, 1, 'Changed blockstates require review');
    candidate = jar({ 'assets/ae2/blockstates/budding_quartz.json': '{}' });
    const removed = await planSync(request, services);
    assert.equal(removed.changes.length, 0, 'A release without the overridden assets must not enable compatibility');
    assert.equal(removed.report.inspections.at(-1).status, 'no_matching_assets');

    const future = { ...services, async catalogue(platform, project) {
      return [file(platform, project, '1.21.1', 'old'), file(platform, project, '27.1', 'future'), file(platform, project, '1.12.2', 'legacy')];
    } };
    const unknown = await planSync(request, future);
    assert.deepEqual(unknown.report.unknownMinecraftVersions, ['27.1']);
    assert.equal(unknown.changes.length, 0, 'Do not enable Minecraft releases missing from the matrix');

    const failed = { ...services, async catalogue() { throw Error('HTTP 503'); } };
    await assert.rejects(planSync(request, failed), /503/);
    assert.equal(fs.readFileSync(configFile, 'utf8'), original, 'Network failure must preserve configuration');
    assert.throws(() => normalizeModrinth([{ project_id: 'wrong' }], 'Ab12Cd34'), /Unexpected/);
    assert.throws(() => normalizeCurseForge({ id: 999, files: [] }, '12345'), /Unexpected/);
    assert.equal(normalizeModrinth([{ project_id: 'Ab12Cd34', status: 'draft', files: [] }], 'Ab12Cd34').length, 0);
    const official = normalizeCurseForge([{ modId: 12345, id: 9000, isAvailable: true, fileName: 'mod.jar', gameVersions: ['26.2', 'NeoForge'], downloadUrl: 'https://example.invalid/mod.jar', hashes: [{ algo: 1, value: 'abcd' }], fileDate: '2026-01-01' }], '12345', true);
    assert.deepEqual(official[0].loaders, ['neoforge']);
    assert.deepEqual(official[0].hashes, { sha1: 'abcd' });
    assert.deepEqual(applyEdits('first second', [{ start: 0, end: 5, value: '1' }, { start: 6, end: 12, value: '2' }]), '1 2');

    // Exercise the actual PowerShell AST offsets and apply/check/idempotency path
    // using cached, synthetic platform catalogues and JARs (no network).
    if (process.platform === 'win32') {
      fs.mkdirSync(path.join(root, 'scripts'), { recursive: true }); fs.mkdirSync(path.join(root, 'config'), { recursive: true });
      for (const name of ['sync-mod-compatibility.ps1', 'sync-mod-compatibility.cjs']) fs.copyFileSync(path.join(__dirname, name), path.join(root, 'scripts', name));
      fs.writeFileSync(path.join(root, 'config/minecraft-release-version-matrix.psd1'), "@{ Versions = @(@{ Id = '1.16.5' }, @{ Id = '1.21.1' }, @{ Id = '26.2' }) }");
      fs.writeFileSync(path.join(root, 'config/compatibility-sync.json'), JSON.stringify({ packs: [{ name: 'fixture', groups: request.packs[0].groups }] }));
      const cache = path.join(root, 'cache/compatibility-sync'); fs.mkdirSync(cache, { recursive: true });
      fs.writeFileSync(path.join(cache, 'modrinth-Ab12Cd34.json'), JSON.stringify([{ project_id: 'Ab12Cd34', status: 'listed', id: 'old', game_versions: ['1.21.1'], loaders: ['forge'], date_published: '2026-01-01', files: [{ primary: true, filename: 'mod.jar', url: 'https://example.invalid/mod.jar', hashes: {} }] }]));
      fs.writeFileSync(path.join(cache, 'curseforge-12345.json'), JSON.stringify({ id: 12345, files: ['1.21.1', '26.2'].map((version, index) => ({ id: 1000 + index, name: 'mod.jar', versions: [version, 'Forge'], uploaded_at: '2026-01-01' })) }));
      for (const key of ['modrinth-old', 'curseforge-1000', 'curseforge-1001']) fs.writeFileSync(path.join(cache, `${key}.jar`), storedZip(upstream));
      const env = { ...process.env, CURSEFORGE_API_KEY: '' };
      const run = args => execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(root, 'scripts/sync-mod-compatibility.ps1'), '-CachedMetadata', ...args], { env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      assert.match(run(['-Check']), /Would update 2 files/);
      assert.equal(fs.readFileSync(configFile, 'utf8'), original);
      assert.match(run([]), /Updated 2 files/);
      assert.equal(fs.readFileSync(configFile, 'utf8'), updated);
      assert.match(run([]), /Updated 0 files/, 'Repeated synchronization must be idempotent');
      // Projects hosted only on CurseForge must not require a Modrinth mapping.
      fs.writeFileSync(path.join(root, 'config/compatibility-sync.json'), JSON.stringify({ packs: [{ name: 'fixture', groups: [{ namespaces: [namespace], projects: [{ curseforge: '12345' }] }] }] }));
      assert.match(run([]), /Updated 0 files/, 'CurseForge-only synchronization profiles must work');
      fs.writeFileSync(path.join(cache, 'curseforge-12345.json'), '{}');
      assert.throws(() => run([]), /Command failed/);
      assert.equal(fs.readFileSync(configFile, 'utf8'), updated);
    }
    console.log('Passed CurseForge-only new releases, platform separation, routing updates, changed/removed assets, network failures, formatting, PSD1 application, check mode and idempotency.');
  } finally {
    assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    fs.rmSync(root, { recursive: true, force: true });
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
