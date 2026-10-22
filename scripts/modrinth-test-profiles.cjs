// Profile discovery is read only. Group changes are limited to an explicit instance ID.
// Authentication tables are never queried.
const fs = require('node:fs');
const path = require('node:path');
const LOADER_GROUPS = Object.freeze({ vanilla: 'Vanilla', fabric: 'Fabric', neoforge: 'NeoForge', forge: 'Forge' });

function ensureLoaderGroupsInTransaction(db) {
  const { randomUUID } = require('node:crypto');
  const result = {};
  for (const [loader, name] of Object.entries(LOADER_GROUPS)) {
    const matches = db.prepare('SELECT id, name, display_order FROM instance_groups ORDER BY display_order, id').all()
      .filter(group => group.name.trim().toLowerCase() === name.toLowerCase());
    // Keep an existing correctly named group and its ID whenever possible.
    let group = matches.find(group => group.name === name) || matches[0];
    if (!group) {
      group = { id: randomUUID() };
      db.prepare('INSERT INTO instance_groups(id, name, display_order) VALUES (?, ?, (SELECT COALESCE(MAX(display_order), -1) + 1 FROM instance_groups))').run(group.id, name);
    }
    for (const duplicate of matches) {
      if (duplicate.id === group.id) continue;
      db.prepare('INSERT OR IGNORE INTO instance_group_memberships(instance_id, group_id) SELECT instance_id, ? FROM instance_group_memberships WHERE group_id = ?').run(group.id, duplicate.id);
      db.prepare('DELETE FROM instance_group_memberships WHERE group_id = ?').run(duplicate.id);
      db.prepare('DELETE FROM instance_groups WHERE id = ?').run(duplicate.id);
    }
    db.prepare('UPDATE instance_groups SET name = ? WHERE id = ?').run(name, group.id);
    result[loader] = { groupId: group.id, groupName: name };
  }
  return result;
}

function ensureLoaderGroups(appDataRoot) {
  const { DatabaseSync } = require('node:sqlite');
  const databasePath = path.join(appDataRoot, 'app.db');
  if (!fs.existsSync(databasePath)) throw new Error(`Modrinth App database not found: ${databasePath}`);
  const db = new DatabaseSync(databasePath);
  try {
    db.exec('PRAGMA busy_timeout = 5000; PRAGMA foreign_keys = ON; BEGIN IMMEDIATE');
    try {
      const groups = ensureLoaderGroupsInTransaction(db);
      db.exec('COMMIT');
      return groups;
    } catch (error) { db.exec('ROLLBACK'); throw error; }
  } finally { db.close(); }
}

function readProfiles(appDataRoot) {
  const { DatabaseSync } = require('node:sqlite');
  const databasePath = path.join(appDataRoot, 'app.db');
  if (!fs.existsSync(databasePath)) throw new Error(`Modrinth App database not found: ${databasePath}`);
  const db = new DatabaseSync(databasePath, { readOnly: true });
  try {
    const settings = db.prepare('SELECT custom_dir FROM settings LIMIT 1').get();
    const profilesRoot = path.resolve(settings?.custom_dir || appDataRoot, 'profiles');
    const rows = db.prepare(`
      SELECT i.id, i.name, i.path, i.install_stage, c.game_version, c.loader,
        EXISTS(SELECT 1 FROM instance_group_memberships m
          JOIN instance_groups g ON g.id = m.group_id
          WHERE m.instance_id = i.id AND g.name = 'Vanilla' COLLATE NOCASE) AS in_vanilla_group
      FROM instances i
      JOIN instance_content_sets c ON c.id = i.applied_content_set_id
      ORDER BY i.name, i.path
    `).all();
    return rows.map(row => {
      const profileDirectory = path.resolve(profilesRoot, row.path);
      const relative = path.relative(profilesRoot, profileDirectory);
      if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
        throw new Error(`Profile directory is outside the Modrinth profiles folder: ${row.name}`);
      }
      return {
        id: row.id, name: row.name, minecraftVersion: row.game_version,
        loader: row.loader, installStage: row.install_stage, profileDirectory,
        inVanillaGroup: Boolean(row.in_vanilla_group),
        groups: db.prepare(`SELECT g.name FROM instance_group_memberships m
          JOIN instance_groups g ON g.id = m.group_id WHERE m.instance_id = ?`).all(row.id).map(group => group.name),
      };
    }).filter(profile => fs.existsSync(profile.profileDirectory) || profile.installStage !== 'installed');
  } finally {
    db.close();
  }
}

function addToLoaderGroup(appDataRoot, instanceId, loader) {
  const groupName = LOADER_GROUPS[loader];
  if (!groupName) throw new Error('Unsupported test profile loader.');
  const { DatabaseSync } = require('node:sqlite');
  const databasePath = path.join(appDataRoot, 'app.db');
  if (!fs.existsSync(databasePath)) throw new Error(`Modrinth App database not found: ${databasePath}`);
  const db = new DatabaseSync(databasePath);
  try {
    db.exec('PRAGMA busy_timeout = 5000; PRAGMA foreign_keys = ON; BEGIN IMMEDIATE');
    try {
      const instance = db.prepare(`SELECT c.loader FROM instances i
        JOIN instance_content_sets c ON c.id = i.applied_content_set_id WHERE i.id = ?`).get(instanceId);
      if (!instance || instance.loader !== loader) throw new Error(`Only an existing ${loader} test profile can be added to the ${groupName} group.`);
      const group = ensureLoaderGroupsInTransaction(db)[loader];
      db.prepare('INSERT OR IGNORE INTO instance_group_memberships(instance_id, group_id) VALUES (?, ?)').run(instanceId, group.groupId);
      db.exec('COMMIT');
      return { instanceId, groupId: group.groupId, groupName };
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  } finally {
    db.close();
  }
}

function addToVanillaGroup(appDataRoot, instanceId) { return addToLoaderGroup(appDataRoot, instanceId, 'vanilla'); }
module.exports = { readProfiles, addToVanillaGroup, addToLoaderGroup, ensureLoaderGroups };
if (require.main === module) {
  try {
    if (!process.argv[2]) throw new Error('Supply the Modrinth App data folder.');
    const result = process.argv[3] === '--ensure-loader-groups'
      ? ensureLoaderGroups(process.argv[2])
      : process.argv[3] === '--group-loader'
      ? addToLoaderGroup(process.argv[2], process.argv[4], process.argv[5])
      : process.argv[3] === '--group-vanilla'
      ? addToVanillaGroup(process.argv[2], process.argv[4])
      : readProfiles(process.argv[2]);
    process.stdout.write(JSON.stringify(result));
  } catch (error) {
    process.stderr.write(`Unable to manage Modrinth test profiles: ${error.message}\n`);
    process.exitCode = 1;
  }
}
