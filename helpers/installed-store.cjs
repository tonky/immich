// Read installed state without invoking pnpm (whose default store probe writes to cwd).
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

try {
  const root = process.argv[2];
  const text = fs.readFileSync(path.join(root, 'node_modules/.modules.yaml'), 'utf8');
  let yaml;
  try {
    yaml = createRequire(path.join(root, 'server/package.json'))('js-yaml');
  } catch {}
  // pnpm 12's JSON needs no extra dependency in a sparse install lacking the server.
  const installed = yaml ? yaml.load(text, { schema: yaml.JSON_SCHEMA }) : JSON.parse(text);
  const store = installed?.storeDir;
  if (typeof store !== 'string' || !path.isAbsolute(store) || /[\x00-\x1f\x7f]/.test(store)) {
    process.exit(1);
  }
  if (!fs.statSync(store).isDirectory()) process.exit(1);
  process.stdout.write(store);
} catch {
  // Missing/unsupported installed state keeps pnpm's normal resolution and cold path.
  process.exit(1);
}
