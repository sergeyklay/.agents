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

async function policyEngineFor(engineModule, policyPath) {
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

function compiledRuleLines(engineModule, engine) {
  const lines = [`rules\t${engine.rules.length}`];
  for (const rule of engine.rules) {
    if (rule.argsPattern) {
      lines.push(`pattern\t${rule.argsPattern.source}`);
    }
    if (rule.decision === engineModule.PolicyDecision.DENY) {
      const { errorMessage } = engineModule.getPolicyDenialError(null, rule);
      lines.push(`denial\t${errorMessage}`);
    }
  }
  return lines;
}

// The dotenv rule covers two tools whose arguments are not a single string, so a
// spec starting with `{` is a whole JSON tool call rather than a shell command.
function toToolCall(spec) {
  return spec.startsWith('{')
    ? JSON.parse(spec)
    : { name: 'run_shell_command', args: { command: spec } };
}

async function decisionLines(engine, specs) {
  const lines = [];
  for (const spec of specs) {
    const { decision } = await engine.check(toToolCall(spec));
    lines.push(`${decision}\t${spec}`);
  }
  return lines;
}

const [bundleEntry, policyPath, ...specs] = process.argv.slice(2);
const engineModule = await import(
  pathToFileURL(findPolicyEngineChunk(bundleEntry)).href
);
const engine = await policyEngineFor(engineModule, policyPath);
const lines =
  specs[0] === '--rules'
    ? compiledRuleLines(engineModule, engine)
    : await decisionLines(engine, specs);
process.stdout.write(`${lines.join('\n')}\n`);
