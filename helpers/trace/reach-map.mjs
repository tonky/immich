// Reach map assembly for generate-reach-map.sh (run from the repository root).
//
//   merge <out.json> <in.json>...    one map from the per-spec maps `enact trace run` wrote
//   coverage <map.json> <windows>    adds to each e2e spec the server sources it ran
//
// <windows> holds one directory per coverage window: `000-boot` (server start-up), then
// one per spec, with a `target` file naming it. A spec's server footprint is:
//   - every source with code that ran during its window (functions with a count), and
//   - the declaration-only sources those import: files loaded at start-up whose code
//     never runs in any window (DTOs, enums, constants, schema), whose decorators and
//     values shape what runs.
// A loaded declaration-only file no executed file imports could matter to any spec, so
// every spec gets it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = process.cwd();

/** Repository-relative paths of a footprint's `files`/`dirs`: a flat list or a trie. */
const flatten = (node, prefix = '') => {
  if (!node) return [];
  if (Array.isArray(node)) return node.map((file) => join(prefix, file));
  return Object.entries(node).flatMap(([key, child]) => flatten(child, key === '.' ? prefix : join(prefix, key)));
};
const join = (dir, file) => (dir ? `${dir}/${file}` : file);

const readMap = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));

const writeMap = (file, map) => {
  const targets = Object.fromEntries(
    Object.entries(map.targets)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([target, fp]) => [target, { files: [...fp.files].sort(), dirs: [...fp.dirs].sort() }]),
  );
  fs.writeFileSync(file, JSON.stringify({ ...map, version: 1, targets }));
};

/** Targets as `{files: Set, dirs: Set}`. */
const footprints = (map) =>
  Object.fromEntries(
    Object.entries(map.targets ?? {}).map(([target, fp]) => [
      target,
      { files: new Set(flatten(fp.files)), dirs: new Set(flatten(fp.dirs)) },
    ]),
  );

const merge = (out, inputs) => {
  const targets = {};
  for (const input of inputs) {
    for (const [target, fp] of Object.entries(footprints(readMap(input)))) {
      const into = (targets[target] ??= { files: new Set(), dirs: new Set() });
      fp.files.forEach((f) => into.files.add(f));
      fp.dirs.forEach((d) => into.dirs.add(d));
    }
  }
  writeMap(out, { targets });
  console.log(`🧩 merged ${inputs.length} maps: ${Object.keys(targets).length} targets → ${out}`);
};

// --- coverage -----------------------------------------------------------------------

/** Repository-relative path of a script URL, or null outside the repository's own code. */
const scriptPath = (url) => {
  if (!url.startsWith('file://')) return null;
  const rel = path.relative(root, fileURLToPath(url));
  return rel.startsWith('..') || rel.split('/').includes('node_modules') ? null : rel;
};

const sourceCache = new Map();
/** The source a compiled file came from (its source map's), else the file itself. */
const sourceOf = (rel) => {
  if (!sourceCache.has(rel)) {
    let source = rel;
    try {
      const map = JSON.parse(fs.readFileSync(`${rel}.map`, 'utf8'));
      const dir = path.dirname(rel);
      source = path.normalize(path.join(dir, map.sourceRoot ?? '', map.sources[0]));
    } catch {}
    sourceCache.set(rel, source);
  }
  return sourceCache.get(rel);
};

/** Compiled files a compiled file requires relatively (one level). */
const requiresOf = (rel) => {
  let code;
  try {
    code = fs.readFileSync(rel, 'utf8');
  } catch {
    return [];
  }
  const dir = path.dirname(rel);
  return [...code.matchAll(/require\("(\.{1,2}\/[^"]+)"\)/g)]
    .map(([, spec]) => path.join(dir, spec))
    .flatMap((base) => [base, `${base}.js`, `${base}/index.js`].find((f) => fs.statSync(f, { throwIfNoEntry: false })?.isFile()) ?? []);
};

/** Compiled scripts of one window: those loaded, and those with code that ran. */
const readWindow = (dir) => {
  const loaded = new Set();
  const ran = new Set();
  for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    for (const script of JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8')).result) {
      const rel = scriptPath(script.url);
      if (!rel) continue;
      loaded.add(rel);
      if (script.functions.some((fn) => fn.ranges[0].count > 0)) ran.add(rel);
    }
  }
  return { loaded, ran };
};

const coverage = (mapFile, windowsDir) => {
  const map = readMap(mapFile);
  const targets = footprints(map);
  const windows = fs
    .readdirSync(windowsDir)
    .sort()
    .map((name) => {
      const dir = path.join(windowsDir, name);
      const targetFile = path.join(dir, 'target');
      const target = fs.existsSync(targetFile) ? fs.readFileSync(targetFile, 'utf8').trim() : null;
      return { name, target, ...readWindow(dir) };
    });
  const specs = windows.filter((w) => w.target);
  if (specs.length === 0) throw new Error(`no spec windows in ${windowsDir}`);

  const loaded = new Set(windows.flatMap((w) => [...w.loaded]));
  const ranInSomeSpec = new Set(specs.flatMap((w) => [...w.ran]));
  const declarative = new Set([...loaded].filter((f) => !ranInSomeSpec.has(f)));

  const imported = new Set();
  const serverFootprint = (w) => {
    const decls = [...w.ran].flatMap(requiresOf).filter((f) => declarative.has(f));
    decls.forEach((f) => imported.add(f));
    return new Set([...w.ran, ...decls].map(sourceOf));
  };
  const perSpec = specs.map((w) => [w.target, serverFootprint(w)]);
  const unattributed = [...declarative].filter((f) => !imported.has(f)).map(sourceOf);

  for (const [target, files] of perSpec) {
    const into = (targets[target] ??= { files: new Set(), dirs: new Set() });
    [...files, ...unattributed].forEach((f) => into.files.add(f));
    console.log(`  ${target}: ${files.size} server sources`);
  }
  console.log(
    `📡 ${specs.length} spec windows · ${loaded.size} loaded · ${declarative.size} declaration-only` +
      ` · ${unattributed.length} imported by no executed file (given to every spec)`,
  );
  writeMap(mapFile, { ...map, targets });
};

const [command, ...args] = process.argv.slice(2);
switch (command) {
  case 'merge': {
    merge(args[0], args.slice(1));
    break;
  }
  case 'coverage': {
    coverage(args[0], args[1]);
    break;
  }
  default: {
    console.error('usage: reach-map.mjs merge <out.json> <in.json>... | coverage <map.json> <windows-dir>');
    process.exit(2);
  }
}
