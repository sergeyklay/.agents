// Prints the decision the installed Gemini CLI's own policy engine returns for
// each command, so a test can assert on resolution rather than on the text of
// a rule.
//
// Usage: node policy_decision.mjs <bundle/gemini.js> <policy.toml> <command>...
// Output: one "<decision>\t<command>" line per command, in argument order.
//
// With --rules in place of the commands it prints what the loader compiled
// instead: a "rules\t<count>" line, then one "pattern\t<source>" line per rule
// that carries an argsPattern. A rule the loader rejects is dropped without an
// error, so the count and the pattern list are what distinguish a policy that
// is in force from one that silently loaded nothing.

import { readFileSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';
import { pathToFileURL } from 'node:url';

const [entry, policyPath, ...commands] = process.argv.slice(2);

// The bundle is split into generated chunks and re-emits the same module into
// several of them; only the chunks the entry point imports are ever loaded, and
// a dead copy carries the same symbols as the live one. Walk the static import
// closure so the module read here is the module that runs.
const SPECIFIER = /(?:from|import)\s*\(?\s*["'](\.[^"']*)["']/g;

function reachable(from) {
  const seen = new Set();
  const pending = [normalize(from)];
  while (pending.length > 0) {
    const file = pending.pop();
    if (seen.has(file)) {
      continue;
    }
    let source;
    try {
      source = readFileSync(file, 'utf-8');
    } catch {
      continue;
    }
    seen.add(file);
    for (const [, specifier] of source.matchAll(SPECIFIER)) {
      pending.push(normalize(join(dirname(file), specifier)));
    }
  }
  return seen;
}

const EXPORTS = /\nexport\s*\{[^}]*\bloadPoliciesFromToml\b[^}]*\}/;

let policyModule;
for (const file of reachable(entry)) {
  if (EXPORTS.test(readFileSync(file, 'utf-8'))) {
    policyModule = file;
    break;
  }
}
if (!policyModule) {
  throw new Error(`no reachable chunk of ${entry} exports loadPoliciesFromToml`);
}

const core = await import(pathToFileURL(policyModule).href);

// The engine's own debug logger calls console.debug unconditionally.
console.debug = () => {};

const loaded = await core.loadPoliciesFromToml(
  [policyPath],
  () => core.WORKSPACE_POLICY_TIER,
);
// A rule the loader rejects is dropped silently and the run continues under
// whatever survived, so a green assertion below would mean nothing.
if (loaded.errors.length > 0) {
  throw new Error(`policy errors: ${JSON.stringify(loaded.errors)}`);
}

const engine = new core.PolicyEngine({
  rules: loaded.rules,
  defaultDecision: core.PolicyDecision.ASK_USER,
  nonInteractive: false,
  approvalMode: core.ApprovalMode.DEFAULT,
});

if (commands[0] === '--rules') {
  const lines = [`rules\t${loaded.rules.length}`];
  for (const rule of loaded.rules) {
    if (rule.argsPattern) {
      lines.push(`pattern\t${rule.argsPattern.source}`);
    }
  }
  process.stdout.write(`${lines.join('\n')}\n`);
  process.exit(0);
}

const lines = [];
for (const command of commands) {
  const { decision } = await engine.check({
    name: 'run_shell_command',
    args: { command },
  });
  lines.push(`${decision}\t${command}`);
}
process.stdout.write(`${lines.join('\n')}\n`);
