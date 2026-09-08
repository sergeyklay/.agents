import { readFileSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';
import { pathToFileURL } from 'node:url';

const RELATIVE_IMPORT = /(?:from|import)\s*\(?\s*["'](\.[^"']*)["']/g;
const EXPORTS_SETTINGS_SCHEMA = /^export\s*\{[^}]*\bgetSettingsSchema\b[^}]*\}/m;

function staticImportClosure(entry) {
  const reached = new Set();
  const pending = [normalize(entry)];
  while (pending.length > 0) {
    const file = pending.pop();
    if (reached.has(file)) {
      continue;
    }
    let source;
    try {
      source = readFileSync(file, 'utf-8');
    } catch {
      continue;
    }
    reached.add(file);
    for (const [, specifier] of source.matchAll(RELATIVE_IMPORT)) {
      pending.push(normalize(join(dirname(file), specifier)));
    }
  }
  return reached;
}

// Six files under bundle/ mention getSettingsSchema on 0.58.0 and only one is
// reachable from the entry, so a directory-wide search names dead chunks.
function findSettingsChunk(bundleEntry) {
  for (const file of staticImportClosure(bundleEntry)) {
    if (EXPORTS_SETTINGS_SCHEMA.test(readFileSync(file, 'utf-8'))) {
      return file;
    }
  }
  throw new Error(`no reachable chunk of ${bundleEntry} exports getSettingsSchema`);
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function childNodeFor(node, name) {
  return node.properties?.[name] ?? node.additionalProperties;
}

// An `additionalProperties` child is an opaque `ref` this schema does not
// expand, so each line names the deepest path the schema can still rule on.
function* keyVerdicts(value, node, path) {
  const listsChildren = Boolean(node.properties || node.additionalProperties);
  if (!isRecord(value) || !listsChildren) {
    yield `known\t${path}`;
    return;
  }
  for (const [name, child] of Object.entries(value)) {
    const childPath = path ? `${path}.${name}` : name;
    const childNode = childNodeFor(node, name);
    if (childNode) {
      yield* keyVerdicts(child, childNode, childPath);
    } else {
      yield `unknown\t${childPath}`;
    }
  }
}

function diagnosticLines(settings) {
  return settings.errors.map(
    (error) => `diagnostic\t${error.message.replaceAll('\n', ' ')}`,
  );
}

const [bundleEntry, settingsPath, workspaceDir] = process.argv.slice(2);
const schemaModule = await import(
  pathToFileURL(findSettingsChunk(bundleEntry)).href
);
const installed = JSON.parse(readFileSync(settingsPath, 'utf-8'));
const lines = [
  ...keyVerdicts(installed, { properties: schemaModule.getSettingsSchema() }, ''),
  ...diagnosticLines(schemaModule.loadSettings(workspaceDir)),
];
process.stdout.write(`${lines.join('\n')}\n`);
