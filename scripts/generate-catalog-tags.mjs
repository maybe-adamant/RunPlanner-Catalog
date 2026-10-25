// Regenerates scripts/catalog-tags.json, the tag lookup catalog-import.ps1 uses, from a local
// Run Planner checkout's game catalog:
//   node scripts/generate-catalog-tags.mjs <path-to-RunPlanner-checkout>
// The checkout needs its dependencies installed (npm ci).
import { existsSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const argument = process.argv[2];
if (argument === undefined) {
  process.stderr.write('usage: node scripts/generate-catalog-tags.mjs <path-to-RunPlanner-checkout>\n');
  process.exit(2);
}
const planner = resolve(argument);
const catalogEntry = join(planner, 'packages', 'hades2-catalog', 'src', 'index.ts');
const vite = join(planner, 'node_modules', 'vite', 'dist', 'node', 'index.js');
if (!existsSync(catalogEntry) || !existsSync(vite)) {
  process.stderr.write(`${planner} has no game catalog or installed dependencies (npm ci).\n`);
  process.exit(1);
}

const { runnerImport } = await import(pathToFileURL(vite).href);
const { module } = await runnerImport(catalogEntry, {
  root: planner,
  configFile: false,
  logLevel: 'silent',
});
const { catalog } = module;

const slug = (text) =>
  text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
const sortedObject = (entries) =>
  Object.fromEntries([...entries].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

const weapons = sortedObject(
  catalog.weapons.values.map((weapon) => [
    weapon.key,
    { tag: slug(weapon.shortLabel), name: weapon.shortLabel },
  ]),
);

// Aspect of Melinoë is every weapon's base aspect; the catalog's entries call it "mel".
const aspects = sortedObject(
  catalog.aspects.values.map((aspect) => {
    const name = aspect.label.replace(/^Aspect of (the )?/, '');
    const tag = slug(name) === 'melinoe' ? 'mel' : slug(name);
    return [aspect.key, { tag, name }];
  }),
);

// Olympian boons by trait key; a Duo is listed by both of its gods.
const olympians = catalog.traitGivers.values.filter((giver) => giver.providerKind === 'olympian');
const boonGods = new Map();
for (const giver of olympians) {
  for (const traitKey of giver.traitKeys) {
    boonGods.set(traitKey, [...(boonGods.get(traitKey) ?? []), slug(giver.label)]);
  }
}
const boons = sortedObject([...boonGods].map(([key, gods]) => [key, [...gods].sort()]));

const routes = sortedObject(
  catalog.routes.values.map((route) => [
    route.key,
    {
      label: route.label,
      ...(route.initialProfile?.fixedWeaponKey === undefined
        ? {}
        : { fixedWeaponKey: route.initialProfile.fixedWeaponKey }),
    },
  ]),
);

const out = join(dirname(fileURLToPath(import.meta.url)), 'catalog-tags.json');
writeFileSync(
  out,
  `${JSON.stringify({ catalogVersion: catalog.version, weapons, aspects, boons, routes }, null, 2)}\n`,
);
process.stdout.write(
  `Wrote ${out}: ${Object.keys(weapons).length} weapons, ${Object.keys(aspects).length} aspects, ` +
    `${Object.keys(boons).length} boons, ${Object.keys(routes).length} routes (catalog ${catalog.version}).\n`,
);
process.exit(0);
