import { readFileSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';
import { pathToFileURL } from 'node:url';

const RELATIVE_IMPORT = /(?:from|import)\s*\(?\s*["'](\.[^"']*)["']/g;
const EXPORTS_POLICY_LOADER = /^export\s*\{[^}]*\bloadPoliciesFromToml\b[^}]*\}/m;

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

function findPolicyEngineChunk(bundleEntry) {
  for (const file of staticImportClosure(bundleEntry)) {
    if (EXPORTS_POLICY_LOADER.test(readFileSync(file, 'utf-8'))) {
      return file;
    }
  }
  throw new Error(`no reachable chunk of ${bundleEntry} exports loadPoliciesFromToml`);
}

async function policyEngineFor(bundleEntry, policyPath) {
  const engineModule = await import(pathToFileURL(findPolicyEngineChunk(bundleEntry)).href);
  console.debug = () => {};
  const { rules, errors } = await engineModule.loadPoliciesFromToml(
    [policyPath],
    () => engineModule.WORKSPACE_POLICY_TIER,
  );
  if (errors.length > 0) {
    throw new Error(
      `rejected rules are dropped and the run continues without them: ${JSON.stringify(errors)}`,
    );
  }
  return new engineModule.PolicyEngine({
    rules,
    defaultDecision: engineModule.PolicyDecision.ASK_USER,
    nonInteractive: false,
    approvalMode: engineModule.ApprovalMode.DEFAULT,
  });
}

function compiledRuleLines(engine) {
  const lines = [`rules\t${engine.rules.length}`];
  for (const rule of engine.rules) {
    if (rule.argsPattern) {
      lines.push(`pattern\t${rule.argsPattern.source}`);
    }
  }
  return lines;
}

async function decisionLines(engine, commands) {
  const lines = [];
  for (const command of commands) {
    const { decision } = await engine.check({
      name: 'run_shell_command',
      args: { command },
    });
    lines.push(`${decision}\t${command}`);
  }
  return lines;
}

const [bundleEntry, policyPath, ...commands] = process.argv.slice(2);
const engine = await policyEngineFor(bundleEntry, policyPath);
const lines =
  commands[0] === '--rules'
    ? compiledRuleLines(engine)
    : await decisionLines(engine, commands);
process.stdout.write(`${lines.join('\n')}\n`);
