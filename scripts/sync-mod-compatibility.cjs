// Network/asset inspection and a read-only edit plan; the PowerShell entry point
// owns PSD1 parsing, validation and applying changes.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const readText = file => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
const readJson = file => JSON.parse(readText(file));
const userAgent = 'Resource-Packs-Manager/compatibility-sync';

async function getResponse(url, headers = {}) {
  const response = await fetch(url, { headers: { 'User-Agent': userAgent, ...headers }, signal: AbortSignal.timeout(120000) });
  if (!response.ok) throw Error(`HTTP ${response.status} while reading ${new URL(url).hostname}${new URL(url).pathname}`);
  return response;
}

function zipEntries(buffer) {
  let end = buffer.length - 22;
  while (end >= Math.max(0, buffer.length - 65557) && buffer.readUInt32LE(end) !== 0x06054b50) end--;
  if (end < 0 || buffer.readUInt32LE(end) !== 0x06054b50) throw Error('Invalid JAR central directory.');
  const entries = new Map();
  let offset = buffer.readUInt32LE(end + 16);
  for (let i = 0; i < buffer.readUInt16LE(end + 10); i++) {
    if (buffer.readUInt32LE(offset) !== 0x02014b50) throw Error('Invalid JAR entry.');
    const method = buffer.readUInt16LE(offset + 10), size = buffer.readUInt32LE(offset + 20);
    const length = buffer.readUInt16LE(offset + 28), extra = buffer.readUInt16LE(offset + 30), comment = buffer.readUInt16LE(offset + 32);
    const local = buffer.readUInt32LE(offset + 42), name = buffer.toString('utf8', offset + 46, offset + 46 + length);
    entries.set(name, () => {
      const start = local + 30 + buffer.readUInt16LE(local + 26) + buffer.readUInt16LE(local + 28);
      const bytes = buffer.subarray(start, start + size);
      if (method === 0) return bytes;
      if (method === 8) return zlib.inflateRawSync(bytes, { maxOutputLength: 32 * 1024 * 1024 });
      throw Error(`Unsupported JAR compression ${method}.`);
    });
    offset += 46 + length + extra + comment;
  }
  return entries;
}

function normalizeModrinth(data, project) {
  if (!Array.isArray(data) || data.some(file => file.project_id !== project)) throw Error(`Unexpected Modrinth catalogue for ${project}.`);
  return data.filter(file => file.status === 'listed').flatMap(file => {
    const binary = file.files?.find(item => item.primary && item.filename.endsWith('.jar')) || file.files?.find(item => item.filename.endsWith('.jar'));
    if (!binary) return [];
    if (!Array.isArray(file.game_versions) || !Array.isArray(file.loaders)) throw Error(`Invalid Modrinth file ${file.id}.`);
    return [{ platform: 'modrinth', project, id: file.id, name: binary.filename, versions: file.game_versions,
      loaders: file.loaders, date: file.date_published, download: binary.url, hashes: binary.hashes || {} }];
  });
}

function normalizeCurseForge(data, project, official = false) {
  if (!official && String(data.id) !== project) throw Error(`Unexpected CurseForge catalogue for ${project}.`);
  const files = official ? data : data.files;
  if (!Array.isArray(files)) throw Error(`Invalid CurseForge file list for ${project}.`);
  return files.filter(file => (official ? file.isAvailable : true) && (official ? file.fileName : file.name)?.endsWith('.jar')).map(file => {
    if (official && String(file.modId) !== project) throw Error(`Unexpected CurseForge file project for ${project}.`);
    const name = official ? file.fileName : file.name;
    const versions = official ? file.gameVersions : file.versions;
    if (!Array.isArray(versions)) throw Error(`Invalid CurseForge file ${file.id}.`);
    const id = String(file.id);
    const hashes = official ? Object.fromEntries((file.hashes || []).filter(hash => hash.algo === 1).map(hash => ['sha1', hash.value])) : {};
    return { platform: 'curseforge', project, id, name, versions,
      loaders: versions.filter(version => /^(forge|neoforge|fabric|quilt)$/i.test(version)).map(version => version.toLowerCase()),
      date: official ? file.fileDate : file.uploaded_at,
      download: official ? file.downloadUrl : `https://mediafilez.forgecdn.net/files/${id.slice(0, -3)}/${Number(id.slice(-3))}/${encodeURIComponent(name)}`,
      hashes };
  });
}

function createServices(request) {
  const cache = path.join(request.root, 'cache/compatibility-sync');
  fs.mkdirSync(cache, { recursive: true });
  const catalogues = new Map(), jars = new Map();
  const sources = new Set();
  return {
    sources,
    async catalogue(platform, project) {
      const key = `${platform}-${project}`;
      if (catalogues.has(key)) return catalogues.get(key);
      console.log(`Reading ${platform} releases for ${project}${request.cachedMetadata ? ' (cached)' : ''}...`);
      const official = platform === 'curseforge' && Boolean(process.env.CURSEFORGE_API_KEY);
      const cacheFile = path.join(cache, `${key}${official ? '-official' : ''}.json`);
      let data;
      if (request.cachedMetadata) data = readJson(cacheFile);
      else if (official) {
        data = [];
        for (let index = 0; ; index += 50) {
          if (index >= 10000) throw Error('CurseForge pagination exceeded its API limit; catalogue is incomplete.');
          const page = await (await getResponse(`https://api.curseforge.com/v1/mods/${project}/files?pageSize=50&index=${index}`, { 'x-api-key': process.env.CURSEFORGE_API_KEY })).json();
          if (!Array.isArray(page.data) || !page.pagination || page.pagination.index !== index) throw Error('Invalid CurseForge pagination.');
          data.push(...page.data);
          if (index + page.data.length >= page.pagination.totalCount) break;
          if (page.data.length !== 50) throw Error('Incomplete CurseForge page.');
        }
      } else {
        const url = platform === 'modrinth' ? `https://api.modrinth.com/v2/project/${project}/version` : `https://api.cfwidget.com/${project}`;
        data = await (await getResponse(url)).json();
      }
      const files = platform === 'modrinth' ? normalizeModrinth(data, project) : normalizeCurseForge(data, project, official);
      if (!request.cachedMetadata) fs.writeFileSync(cacheFile, JSON.stringify(data));
      sources.add(platform === 'modrinth' ? 'Modrinth API' : official ? 'CurseForge API (paginated)' : 'CurseForge via public CFWidget index');
      catalogues.set(key, files);
      return files;
    },
    async jar(file) {
      const key = `${file.platform}-${file.id}`;
      if (jars.has(key)) return jars.get(key);
      if (!file.download) throw Error(`Download unavailable for ${key}; cannot verify assets.`);
      const cacheFile = path.join(cache, `${key}.jar`);
      if (!fs.existsSync(cacheFile)) {
        // Reuse earlier release research downloads, if present.
        const research = ['create-research', 'ae2-research', 'mekanism-research'].map(folder => path.join(request.root, 'cache', folder, `${key}-${file.name}`)).find(file => fs.existsSync(file));
        const bytes = research ? fs.readFileSync(research) : Buffer.from(await (await getResponse(file.download)).arrayBuffer());
        zipEntries(bytes); // Do not cache an HTML/error body as a JAR.
        fs.writeFileSync(cacheFile, bytes);
      }
      const bytes = fs.readFileSync(cacheFile);
      for (const algorithm of ['sha512', 'sha1']) {
        if (file.hashes[algorithm] && crypto.createHash(algorithm).update(bytes).digest('hex') !== file.hashes[algorithm].toLowerCase()) throw Error(`Checksum mismatch for ${key}.`);
      }
      const entries = zipEntries(bytes);
      jars.set(key, entries);
      if (jars.size > 4) jars.delete(jars.keys().next().value);
      return entries;
    }
  };
}

function walkFiles(directory, relative = '') {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? walkFiles(path.join(directory, entry.name), `${relative}${entry.name}/`) : [`${relative}${entry.name}`]);
}
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
  return value;
}
function modelIds(value, result = new Set()) {
  if (!value || typeof value !== 'object') return result;
  for (const [key, child] of Object.entries(value)) {
    if (key === 'model' && typeof child === 'string') result.add(child);
    else modelIds(child, result);
  }
  return result;
}
function assetSignature(entries, namespace, targets) {
  const present = targets.filter(target => entries.has(target)).sort();
  if (!present.length) return null;
  const ids = new Set(present.filter(file => file.includes('/models/')).map(file => `${namespace}:${file.split('/models/')[1].replace(/\.json$/, '')}`));
  const states = [];
  for (const [name, read] of entries) {
    if (!name.startsWith(`assets/${namespace}/blockstates/`) || !name.endsWith('.json')) continue;
    const document = JSON.parse(read().toString('utf8'));
    const models = [...modelIds(document)].sort();
    if (!present.includes(name) && !models.some(model => ids.has(model))) continue;
    states.push({ path: name, variants: Object.keys(document.variants || {}).sort(),
      multipart: (document.multipart || []).map(part => stable(part.when || {})), models });
  }
  return JSON.stringify({ paths: present, states: states.sort((a, b) => a.path.localeCompare(b.path)) });
}
function latestFiles(files, version) {
  const winners = new Map();
  for (const file of files.filter(file => file.versions.includes(version)).sort((a, b) => Date.parse(a.date) - Date.parse(b.date))) {
    for (const loader of file.loaders.length ? file.loaders : ['unknown']) winners.set(`${file.platform}/${file.project}/${loader}`, file);
  }
  return [...new Set(winners.values())];
}
function unionOrdered(versions, ...lists) {
  const all = new Set(lists.flat());
  const unknown = [...all].filter(version => !versions.includes(version));
  if (unknown.length) throw Error(`Versions missing from the Minecraft release matrix: ${unknown.join(', ')}`);
  return versions.filter(version => all.has(version));
}

// Parse JSON spans so only changed Versions arrays are replaced. Preserve the
// generated rule file's formatting, ordering and FileVariants unchanged.
function jsonTree(text) {
  const tokens = [...text.matchAll(/"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g)];
  let cursor = 0;
  function parse() {
    const first = tokens[cursor++], node = { start: first.index, properties: {}, children: [] };
    if (first[0] === '{') {
      while (tokens[cursor][0] !== '}') {
        const key = JSON.parse(tokens[cursor++][0]); cursor++;
        node.properties[key] = parse();
        if (tokens[cursor][0] === ',') cursor++;
      }
      node.end = tokens[cursor++].index + 1;
    } else if (first[0] === '[') {
      while (tokens[cursor][0] !== ']') { node.children.push(parse()); if (tokens[cursor][0] === ',') cursor++; }
      node.end = tokens[cursor++].index + 1;
    } else node.end = first.index + first[0].length;
    return node;
  }
  return parse();
}
function applyEdits(text, edits) {
  for (const edit of edits.sort((a, b) => b.start - a.start)) text = text.slice(0, edit.start) + edit.value + text.slice(edit.end);
  return text;
}

async function planSync(request, services = createServices(request)) {
  const changes = [], report = { checkedAtUtc: new Date().toISOString(), cachedMetadata: Boolean(request.cachedMetadata), messages: [], additions: [], inspections: [], needsReview: [], unknownMinecraftVersions: [] };
  const versions = request.versions;
  for (const pack of request.packs) {
    const original = readText(pack.file), updates = new Map(), ruleAdditions = [];
    const keyOf = (kind, key) => `${kind}:${key}`;
    for (const group of pack.groups) {
      const files = (await Promise.all(group.projects.flatMap(project => Object.entries(project).map(async ([platform, id]) => services.catalogue(platform, id))))).flat();
      report.unknownMinecraftVersions.push(...new Set(files.flatMap(file => file.versions).filter(version => /^\d+(?:\.\d+)+$/.test(version) &&
        version.localeCompare(versions[0], 'en', { numeric: true }) >= 0 && !versions.includes(version))));
      const accepted = new Map();
      for (const namespace of group.namespaces) {
        const config = pack.options.Compatibility[namespace];
        if (config.Enabled === false) continue;
        if (config.Paths) throw Error(`${pack.name}/${namespace}: custom Paths need an asset-inspection profile.`);
        const current = config.Versions;
        if (!Array.isArray(current) || !current.length) throw Error(`${pack.name}/${namespace} needs an existing supported version as its reference.`);
        const targets = walkFiles(path.join(pack.root, 'assets', namespace)).map(file => `assets/${namespace}/${file}`)
          .filter(file => /\/(blockstates|models)\/.+\.json$/.test(file) && !file.includes('/alternative_ores/'));
        if (!targets.length) throw Error(`No upstream asset targets found for ${pack.name}/${namespace}.`);
        const signatures = new Map();
        async function signatureFor(file) {
          const key = `${file.platform}:${file.id}`;
          if (!signatures.has(key)) signatures.set(key, assetSignature(await services.jar(file), namespace, targets));
          return signatures.get(key);
        }
        for (const version of versions.filter(version => !current.includes(version))) {
          const candidates = latestFiles(files, version);
          if (!candidates.length) continue;
          console.log(`Checking ${pack.name}/${namespace} for Minecraft ${version} (${candidates.length} release files)...`);
          for (const candidate of candidates) {
            const signature = await signatureFor(candidate);
            const inspection = { pack: pack.name, namespace, version, platform: candidate.platform, project: candidate.project, file: candidate.id };
            if (!signature) {
              report.inspections.push({ ...inspection, status: 'no_matching_assets' });
              continue; // e.g. AE2 releases after ore removal, or its other namespace.
            }
            const donorVersions = [...current].sort((a, b) => Math.abs(versions.indexOf(a) - versions.indexOf(version)) - Math.abs(versions.indexOf(b) - versions.indexOf(version)));
            let donor;
            for (const referenceVersion of donorVersions) {
              const referenceFiles = latestFiles(files, referenceVersion).sort((a, b) => Number(b.project === candidate.project && b.platform === candidate.platform) - Number(a.project === candidate.project && a.platform === candidate.platform));
              for (const reference of referenceFiles) {
                if (await signatureFor(reference) === signature) { donor = referenceVersion; break; }
              }
              if (donor) break;
            }
            if (!donor) {
              report.needsReview.push({ pack: pack.name, namespace, version, platform: candidate.platform, project: candidate.project, file: candidate.id,
                reason: 'Upstream asset paths or blockstate model/property schema differ from known supported releases.' });
              continue;
            }
            report.inspections.push({ ...inspection, status: 'matched', referenceVersion: donor });
            const key = keyOf('compatibility', namespace);
            updates.set(key, unionOrdered(versions, updates.get(key) || current, [version]));
            ruleAdditions.push({ namespace, version, donor });
            const projectKey = `${candidate.platform}:${candidate.project}`;
            if (!accepted.has(projectKey)) accepted.set(projectKey, new Set());
            accepted.get(projectKey).add(version);
          }
        }
      }
      for (const project of group.projects) for (const [platform, id] of Object.entries(project)) {
        const platformName = platform === 'modrinth' ? 'Modrinth' : 'CurseForge';
        const dependency = pack.options[platformName]?.Dependencies?.find(entry => entry.ProjectId === id);
        if (!dependency) throw Error(`${pack.name}: missing ${platformName} dependency ${id}.`);
        if (dependency.Enabled === false) continue;
        // Existing compatibility is trusted; new compatibility needs JAR evidence
        // for this particular platform/project, not just another platform's file.
        const originalSupport = new Set(group.namespaces.filter(namespace => pack.options.Compatibility[namespace].Enabled !== false).flatMap(namespace => pack.options.Compatibility[namespace].Versions));
        const available = files.filter(file => file.platform === platform && file.project === id).flatMap(file => file.versions)
          .filter(version => versions.includes(version) && (originalSupport.has(version) || accepted.get(`${platform}:${id}`)?.has(version)));
        updates.set(keyOf(platform, id), unionOrdered(versions, dependency.Versions, available));
      }
    }
    const edits = [];
    for (const location of pack.locations) {
      const next = updates.get(keyOf(location.kind, location.key));
      if (!next) continue;
      const previous = location.kind === 'compatibility' ? pack.options.Compatibility[location.key].Versions
        : pack.options[location.kind === 'modrinth' ? 'Modrinth' : 'CurseForge'].Dependencies.find(entry => entry.ProjectId === location.key).Versions;
      const added = next.filter(version => !previous.includes(version));
      if (!added.length) continue;
      edits.push({ start: location.start, end: location.end, value: `@(${next.map(version => `'${version}'`).join(', ')})` });
      report.additions.push({ pack: pack.name, kind: location.kind, key: location.key, versions: added });
      report.messages.push(`${pack.name} ${location.kind} ${location.key}: added ${added.join(', ')}`);
    }
    if (edits.length) changes.push({ path: pack.file, original, content: applyEdits(original, edits) });
    if (pack.options.FileOptionsPath && ruleAdditions.length) {
      const file = path.resolve(pack.root, pack.options.FileOptionsPath);
      if (!file.startsWith(pack.root + path.sep)) throw Error('FileOptionsPath escapes its pack.');
      const text = readText(file), json = JSON.parse(text), tree = jsonTree(text), ruleEdits = [];
      for (const [index, rule] of (json.FileRules || []).entries()) {
        if (!Array.isArray(rule.Versions)) continue;
        const additions = ruleAdditions.filter(addition => rule.Path.startsWith(`assets/${addition.namespace}/`) && rule.Versions.includes(addition.donor)).map(addition => addition.version);
        const next = unionOrdered(versions, rule.Versions, additions);
        if (next.length === rule.Versions.length) continue;
        const span = tree.properties.FileRules.children[index].properties.Versions;
        ruleEdits.push({ start: span.start, end: span.end, value: JSON.stringify(next) });
      }
      if (ruleEdits.length) {
        changes.push({ path: file, original: text, content: applyEdits(text, ruleEdits) });
        report.messages.push(`${pack.name}: extended ${ruleEdits.length} asset routing rules using matching release assets.`);
      }
    }
  }
  report.sources = [...services.sources];
  report.unknownMinecraftVersions = [...new Set(report.unknownMinecraftVersions)];
  if (report.unknownMinecraftVersions.length) report.messages.push(`Not in the Minecraft build matrix (not enabled): ${report.unknownMinecraftVersions.join(', ')}`);
  if (report.needsReview.length) report.messages.push(`${report.needsReview.length} release/namespace comparisons need asset review; see report.`);
  if (!changes.length) report.messages.push('No missing compatible versions to add. Existing version entries were preserved.');
  return { changes, report };
}

module.exports = { planSync, normalizeModrinth, normalizeCurseForge, assetSignature, zipEntries, jsonTree, applyEdits, createServices };
if (require.main === module) {
  planSync(readJson(process.argv[2])).then(plan => fs.writeFileSync(process.argv[3], JSON.stringify(plan)))
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}
