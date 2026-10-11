// Lossless formatting: preserve the original string and number tokens.
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

function parse(text) {
  JSON.parse(text); // Reject invalid JSON before making any edits.
  const tokens = text.match(/"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g);
  let index = 0;
  function value() {
    const token = tokens[index++];
    if (token === '{') {
      const entries = [];
      while (tokens[index] !== '}') {
        const key = tokens[index++];
        if (tokens[index++] !== ':') throw new Error('Expected colon');
        entries.push([key, value()]);
        if (tokens[index] !== ',') break;
        index++;
      }
      if (tokens[index++] !== '}') throw new Error('Expected closing brace');
      return { type: 'object', entries };
    }
    if (token === '[') {
      const items = [];
      while (tokens[index] !== ']') {
        items.push(value());
        if (tokens[index] !== ',') break;
        index++;
      }
      if (tokens[index++] !== ']') throw new Error('Expected closing bracket');
      return { type: 'array', items };
    }
    return { type: 'scalar', token };
  }
  const result = value();
  if (index !== tokens.length) throw new Error('Unexpected remaining tokens');
  return result;
}

function inline(node) {
  if (node.type === 'scalar') return node.token;
  if (node.type === 'array' && node.items.every(item => item.type === 'scalar')) {
    return '[' + node.items.map(inline).join(', ') + ']';
  }
  if (node.type === 'object') {
    const parts = node.entries.map(([key, child]) => {
      if (child.type === 'object') return null;
      const result = inline(child);
      return result === null ? null : key + ': ' + result;
    });
    if (parts.every(part => part !== null)) return '{ ' + parts.join(', ') + ' }';
  }
  return null;
}

function format(node, depth = 0, compact = false) {
  const pad = '  '.repeat(depth);
  const childPad = pad + '  ';
  if (node.type === 'scalar') return node.token;
  const short = inline(node);
  if (node.type === 'array' && short !== null) return short;
  if (compact && short !== null && short.length <= 160) return short;
  if (node.type === 'object') {
    if (!node.entries.length) return '{}';
    return '{\n' + node.entries.map(([key, child]) => {
      const name = JSON.parse(key);
      const face = ['up', 'down', 'north', 'south', 'east', 'west', 'rotation'].includes(name);
      return childPad + key + ': ' + format(child, depth + 1, face);
    }).join(',\n') + '\n' + pad + '}';
  }
  if (!node.items.length) return '[]';
  return '[\n' + node.items.map(child => childPad + format(child, depth + 1, true)).join(',\n') + '\n' + pad + ']';
}

module.exports = { parse, format };
if (require.main === module) {
const result = spawnSync('rg', ['--files', '-g', '*.json', '-g', '!build/**', '-g', '!cache/**', '-g', '!archive/**', '-g', '!.idea/**'], { encoding: 'utf8' });
if (result.status !== 0) throw new Error(result.stderr || 'Could not list source JSON files');
const files = result.stdout.trim().split(/\r?\n/).filter(Boolean);
// Validate and format every file before writing any of them.
const outputs = files.map(file => {
  const original = fs.readFileSync(file, 'utf8');
  const formatted = format(parse(original.replace(/^\uFEFF/, ''))) + '\n';
  if (JSON.stringify(JSON.parse(original.replace(/^\uFEFF/, ''))) !== JSON.stringify(JSON.parse(formatted))) {
    throw new Error('Formatting changed JSON content: ' + file);
  }
  return { file, original, formatted };
});
const changed = outputs.filter(output => output.original !== output.formatted);
if (!process.argv.includes('--check')) {
  for (const output of changed) fs.writeFileSync(output.file, output.formatted);
}
console.log(`Validated ${files.length} source JSON files; ${changed.length} ${process.argv.includes('--check') ? 'need formatting' : 'reformatted'}.`);
if (process.argv.includes('--check') && changed.length) process.exitCode = 1;
}
