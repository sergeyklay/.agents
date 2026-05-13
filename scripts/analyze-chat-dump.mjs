#!/usr/bin/env node
// Usage and cost report for a VS Code Copilot Chat export.
import { readFile } from 'node:fs/promises';
import { basename, extname } from 'node:path';
import { parseArgs } from 'node:util';

const log = {
  info: (...a) => process.stdout.write(a.join(' ') + '\n'),
  error: (...a) => process.stderr.write('error: ' + a.join(' ') + '\n'),
};

const USAGE = 'Usage: node scripts/analyze-chat-dump.mjs <path-to-chat.json>';

/**
 * @returns {string} Validated path to the input JSON file.
 */
function parseCliArgs() {
  let positionals;
  try {
    ({ positionals } = parseArgs({
      args: process.argv.slice(2),
      allowPositionals: true,
      strict: true,
    }));
  } catch (err) {
    log.error(err.message);
    process.stderr.write(USAGE + '\n');
    process.exit(1);
  }

  if (positionals.length === 0) {
    log.error('Missing required argument: <path-to-chat.json>');
    process.stderr.write(USAGE + '\n');
    process.exit(1);
  }

  const [inputPath] = positionals;

  if (extname(inputPath).toLowerCase() !== '.json') {
    log.error(`Expected a .json file, got: ${inputPath}`);
    process.exit(1);
  }

  return inputPath;
}

const DASH = '—';
const SEP = '·';
const MS_PER_MINUTE = 60_000;
const MAX_TASK_FALLBACK = 72;
const WRAP_WIDTH = 70;

/** @param {number} ms */
function fmtDuration(ms) {
  const totalMin = Math.floor(ms / MS_PER_MINUTE);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

/** @param {number} ms */
function fmtDate(ms) {
  const d = new Date(ms);
  const pad = (/** @type {number} */ n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** @param {number} ms */
function fmtDateTime(ms) {
  const d = new Date(ms);
  const pad = (/** @type {number} */ n) => String(n).padStart(2, '0');
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}`
  );
}

/** Compact period: `YYYY-MM-DD HH:MM → HH:MM` if same date, else full both. */
function fmtPeriod(startMs, endMs) {
  const start = fmtDateTime(startMs);
  const end = fmtDateTime(endMs);
  const sameDate = start.slice(0, 10) === end.slice(0, 10);
  return `${start} → ${sameDate ? end.slice(11) : end}`;
}

/** @param {number} n */
function fmtInt(n) {
  return n.toLocaleString('en-US');
}

/** @param {number} usd */
function fmtUsd(usd) {
  return `$${usd.toFixed(2)}`;
}

/** @param {number} credits */
function fmtCredits(credits) {
  return credits.toFixed(1);
}

/** Whitespace-aware wrap to a target line width. */
function wrap(text, width) {
  const words = text.split(/\s+/);
  const lines = [];
  let cur = '';
  for (const w of words) {
    if (cur.length === 0) cur = w;
    else if (cur.length + 1 + w.length <= width) cur += ' ' + w;
    else {
      lines.push(cur);
      cur = w;
    }
  }
  if (cur) lines.push(cur);
  return lines;
}

// USD per 1,000,000 tokens. `cacheWrite` falls back to `cachedInput`.
/** @type {Record<string, { input: number, cachedInput: number, cacheWrite?: number, output: number }>} */
const MODEL_PRICES = {
  'gpt-5-mini': { input: 0.25, cachedInput: 0.025, output: 2.0 },
  'raptor-mini': { input: 0.25, cachedInput: 0.025, output: 2.0 },
  'grok-code-fast-1': { input: 0.2, cachedInput: 0.02, output: 1.5 },
  'gpt-4.1': { input: 2.0, cachedInput: 0.5, output: 8.0 },
  'gpt-5.2': { input: 1.75, cachedInput: 0.175, output: 14.0 },
  'gpt-5.2-codex': { input: 1.75, cachedInput: 0.175, output: 14.0 },
  'gpt-5.3-codex': { input: 1.75, cachedInput: 0.175, output: 14.0 },
  'gpt-5.4': { input: 2.5, cachedInput: 0.25, output: 15.0 },
  'gpt-5.4-mini': { input: 0.75, cachedInput: 0.075, output: 4.5 },
  'gpt-5.4-nano': { input: 0.2, cachedInput: 0.02, output: 1.25 },
  'gpt-5.5': { input: 5.0, cachedInput: 0.5, output: 30.0 },
  'claude-haiku-4.5': { input: 1.0, cachedInput: 0.1, cacheWrite: 1.25, output: 5.0 },
  'claude-sonnet-4': { input: 3.0, cachedInput: 0.3, cacheWrite: 3.75, output: 15.0 },
  'claude-sonnet-4.5': { input: 3.0, cachedInput: 0.3, cacheWrite: 3.75, output: 15.0 },
  'claude-sonnet-4.6': { input: 3.0, cachedInput: 0.3, cacheWrite: 3.75, output: 15.0 },
  'claude-opus-4.5': { input: 5.0, cachedInput: 0.5, cacheWrite: 6.25, output: 25.0 },
  'claude-opus-4.6': { input: 5.0, cachedInput: 0.5, cacheWrite: 6.25, output: 25.0 },
  'claude-opus-4.7': { input: 5.0, cachedInput: 0.5, cacheWrite: 6.25, output: 25.0 },
  'gemini-2.5-pro': { input: 1.25, cachedInput: 0.125, output: 10.0 },
  'gemini-3-flash': { input: 0.5, cachedInput: 0.05, output: 3.0 },
  'gemini-3.1-pro': { input: 2.0, cachedInput: 0.2, output: 12.0 },
  goldeneye: { input: 1.25, cachedInput: 0.125, output: 10.0 },
};

/** Retired or differently-named models routed to a priced equivalent. */
const MODEL_ALIASES = {
  'gpt-5.1': 'gpt-5.2',
  'gpt-5.1-codex': 'gpt-5.2-codex',
  'gpt-5.1-codex-mini': 'gpt-5.4-mini',
  'gpt-5.1-codex-max': 'gpt-5.2-codex',
  'gpt-4o': 'gpt-4.1',
  'gpt-4o-mini': 'gpt-5-mini',
  'oswe-vscode-prime': 'raptor-mini',
  'gemini-3-pro': 'gemini-3.1-pro',
  'gemini-3-flash-preview': 'gemini-3-flash',
  'gemini-3-pro-preview': 'gemini-3.1-pro',
  'gemini-3.1-pro-preview': 'gemini-3.1-pro',
};

/**
 * Canonicalize a model identifier (case, vendor prefix, separators) so it can
 * be looked up in MODEL_PRICES.
 *
 * @param {unknown} model
 */
function normalizeModel(model) {
  return String(model ?? '')
    .toLowerCase()
    .replace(/^github-copilot\//, '')
    .replace(/\s*\((preview)\)\s*/g, '-$1')
    .replace(/_/g, '-')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .trim();
}

/**
 * Apply normalization and alias resolution. Returns the priced key when known,
 * else the normalized name (so the caller can surface it as "unpriced").
 *
 * @param {unknown} model
 */
function resolveModel(model) {
  const normalized = normalizeModel(model);
  if (MODEL_PRICES[normalized]) return normalized;
  if (normalized.endsWith('-preview')) {
    const stable = normalized.slice(0, -'-preview'.length);
    if (MODEL_PRICES[stable]) return stable;
  }
  return MODEL_ALIASES[normalized] ?? normalized;
}

/**
 * Extract a canonical, normalized model name from a request. VS Code stores
 * the authoritative model under different fields depending on whether the
 * user selected a specific model or "auto" — `details` wins when it names a
 * model, then `resolvedModel`, then the bare `modelId` minus `copilot/`.
 *
 * @param {any} req
 */
function modelFromRequest(req) {
  const details = String(req?.details ?? '').toLowerCase();
  if (details.includes('claude haiku 4.5')) return 'claude-haiku-4.5';
  if (details.includes('raptor mini')) return 'raptor-mini';
  if (details.includes('gpt-5 mini')) return 'gpt-5-mini';

  const resolved = String(req?.resolvedModel ?? '').toLowerCase();
  if (resolved.includes('gpt-5-mini')) return 'gpt-5-mini';
  if (resolved.includes('grok')) return 'grok-code-fast-1';

  const raw = String(req?.modelId ?? '').replace(/^copilot\//, '');
  return normalizeModel(raw);
}

/**
 * Approximate token count for arbitrary content (~4 chars per token).
 *
 * @param {unknown} value
 */
function roughTokens(value) {
  if (value == null) return 0;
  return Math.ceil(JSON.stringify(value).length / 4);
}

/**
 * Cumulative input tokens billed across the request. For an agentic chat the
 * model is invoked once per tool-call round, each invocation reshipping the
 * initial prompt plus the conversation accumulated so far. The total is
 * approximated as `N * initial + history * (N - 1) / 2`, where `history` is
 * the size of `toolCallRounds + toolCallResults` and the triangular factor
 * reflects history growing one round at a time. Anthropic's
 * metadata.promptTokens reflects only the LAST round and is not used here.
 * For single-shot chats (no rounds) Anthropic's exact count is used when
 * present, falling back to the rendered prompt size.
 *
 * @param {any} req
 * @returns {{ tokens: number, estimated: boolean }}
 */
function inputTokensForRequest(req) {
  const md = req?.result?.metadata ?? {};
  const rounds = Array.isArray(md.toolCallRounds) ? md.toolCallRounds : [];
  const N = rounds.length;

  if (N === 0) {
    const exact = md.promptTokens;
    if (typeof exact === 'number' && Number.isFinite(exact)) {
      return { tokens: exact, estimated: false };
    }
    const initial = roughTokens(md.renderedUserMessage) + roughTokens(md.renderedGlobalContext);
    return { tokens: initial, estimated: true };
  }

  const initial = roughTokens(md.renderedUserMessage) + roughTokens(md.renderedGlobalContext);
  const history = roughTokens(md.toolCallRounds) + roughTokens(md.toolCallResults);
  return {
    tokens: Math.round(N * initial + (history * (N - 1)) / 2),
    estimated: true,
  };
}

/**
 * USD cost for one token bundle at a given rate. cacheRead/cacheWrite are
 * always 0 for VS Code chatSessions (the cache breakdown is not persisted),
 * but the formula carries them so this stays a drop-in for richer sources.
 *
 * @param {{ input: number, cachedInput: number, cacheWrite?: number, output: number }} rate
 * @param {{ input: number, cacheRead: number, cacheWrite: number, output: number }} tokens
 */
function priceTokens(rate, tokens) {
  const nonCachedInput = Math.max(0, tokens.input - tokens.cacheRead);
  return (
    (nonCachedInput * rate.input +
      tokens.cacheRead * rate.cachedInput +
      tokens.cacheWrite * (rate.cacheWrite ?? rate.cachedInput) +
      tokens.output * rate.output) /
    1_000_000
  );
}

/**
 * Fold over requests to produce token totals and USD cost. Tracks any models
 * with no priced rate so the caller can mark the cost as partial.
 *
 * @param {any[]} reqs
 */
function computeCost(reqs) {
  let inputTotal = 0;
  let outputTotal = 0;
  let usdTotal = 0;
  let anyEstimated = false;
  let unpricedCount = 0;
  const unpricedModels = new Set();

  for (const r of reqs) {
    const { tokens: input, estimated } = inputTokensForRequest(r);
    const output = r?.completionTokens ?? 0;
    inputTotal += input;
    outputTotal += output;
    anyEstimated ||= estimated;

    const priced = resolveModel(modelFromRequest(r));
    const rate = MODEL_PRICES[priced];
    if (!rate) {
      unpricedCount += 1;
      unpricedModels.add(priced || 'unspecified');
      continue;
    }
    usdTotal += priceTokens(rate, { input, cacheRead: 0, cacheWrite: 0, output });
  }

  return {
    inputTotal,
    outputTotal,
    inputEstimated: anyEstimated,
    usdTotal,
    creditsTotal: usdTotal * 100,
    unpricedCount,
    unpricedModels: [...unpricedModels].sort(),
  };
}

/**
 * Guard against a historical VS Code bug where `timeSpentWaiting` was
 * serialized as the absolute wait-start timestamp instead of a duration.
 *
 * @param {{ timestamp?: number, timeSpentWaiting?: number }} req
 */
function sanitizedWait(req) {
  const w = req.timeSpentWaiting ?? 0;
  const ts = req.timestamp ?? 0;
  return ts > 0 && w >= ts ? 0 : w;
}

/**
 * Slash commands live in `message.parts[].kind === 'prompt'`.
 *
 * @param {any} req
 */
function extractSlashCommand(req) {
  const parts = req?.message?.parts ?? [];
  const prompt = parts.find((/** @type {any} */ p) => p?.kind === 'prompt');
  return prompt?.name ?? null;
}

/**
 * Task reference from the first user message: every `BP-\d+` in message text
 * and `variableData` attachment names (sorted, comma-joined), falling back to
 * the slash-command argument when no BP id is found.
 *
 * @param {any} req
 * @param {string | null} slash
 */
function extractTaskRef(req, slash) {
  const ids = new Set();
  const text = req?.message?.text ?? '';
  const BP_RE = /\bBP-\d+\b/gi;
  for (const m of text.matchAll(BP_RE)) ids.add(m[0].toUpperCase());

  const vars = req?.variableData?.variables ?? [];
  for (const v of vars) {
    const name = v?.name ?? '';
    for (const m of name.matchAll(BP_RE)) ids.add(m[0].toUpperCase());
  }

  if (ids.size > 0) {
    return [...ids]
      .sort((a, b) => Number(a.slice(3)) - Number(b.slice(3)))
      .join(', ');
  }

  if (slash && text.startsWith(`/${slash}`)) {
    const rest = text.slice(`/${slash}`.length).split('\n')[0].trim();
    if (rest) {
      return rest.length > MAX_TASK_FALLBACK
        ? rest.slice(0, MAX_TASK_FALLBACK - 1).trimEnd() + '…'
        : rest;
    }
  }

  return null;
}

/**
 * Human-readable orchestrator name. VS Code stores the loaded agent file's
 * display name in `modeInfo.modeInstructions.name` (e.g. "ImplPipeline" when
 * the user activated /implPipeline). Falls back to `modeInfo.modeId`, then
 * to a generic label.
 *
 * @param {any} req
 */
function extractOrchestratorName(req) {
  return req?.modeInfo?.modeInstructions?.name || req?.modeInfo?.modeId || 'Generic';
}

/**
 * @param {{ requests?: any[] }} chat
 */
function analyze(chat) {
  const reqs = Array.isArray(chat.requests) ? chat.requests : [];
  if (reqs.length === 0) return null;

  const first = reqs.reduce((a, b) => (a.timestamp < b.timestamp ? a : b));
  const last = reqs.reduce((a, b) => (a.timestamp > b.timestamp ? a : b));

  const start = first.timestamp;
  const end = (last.timestamp ?? 0) + (last.elapsedMs ?? 0) + sanitizedWait(last);

  const slash = extractSlashCommand(first);
  const taskRef = extractTaskRef(first, slash);
  const orchName = extractOrchestratorName(first);

  let totalWait = 0;

  // Indexed by the launch's toolCallId so nested invocations
  // (subAgentInvocationId) can be attributed to their owning (name, model).
  /** @type {Map<string, { name: string, model: string }>} */
  const launchById = new Map();

  // The orchestrator participates as an agent on equal footing: `launches`
  // counts requests for it and runSubagent invocations for subagents.
  /** @type {Map<string, { name: string, model: string, launches: number, toolCalls: number }>} */
  const agents = new Map();

  // Tools aggregate over models per agent; the model dimension is preserved
  // in `agents` above and intentionally dropped here.
  /** @type {Map<string, { agent: string, tool: string, count: number }>} */
  const tools = new Map();

  const agentKey = (/** @type {string} */ name, /** @type {string} */ model) =>
    `${name}${model}`;

  const bumpAgent = (
    /** @type {string} */ name,
    /** @type {string} */ model,
    /** @type {'launches' | 'toolCalls'} */ field,
  ) => {
    const k = agentKey(name, model);
    const a = agents.get(k) ?? { name, model, launches: 0, toolCalls: 0 };
    a[field] += 1;
    agents.set(k, a);
  };

  const bumpTool = (/** @type {string} */ agent, /** @type {string} */ tool) => {
    const k = `${agent}${tool}`;
    const t = tools.get(k) ?? { agent, tool, count: 0 };
    t.count += 1;
    tools.set(k, t);
  };

  for (const r of reqs) {
    totalWait += sanitizedWait(r);
    const orchModel = modelFromRequest(r);
    bumpAgent(orchName, orchModel, 'launches');

    const resp = Array.isArray(r.response) ? r.response : [];

    // Pass 1 — register every subagent launch.
    for (const item of resp) {
      if (item?.kind !== 'toolInvocationSerialized') continue;
      const tsd = item.toolSpecificData;
      if (tsd?.kind !== 'subagent') continue;
      const name = tsd.agentName || '(ad-hoc)';
      const model = normalizeModel(tsd.modelName ?? '') || DASH;
      if (item.toolCallId) launchById.set(item.toolCallId, { name, model });
      bumpAgent(name, model, 'launches');
    }

    // Pass 2 — attribute each tool invocation.
    for (const item of resp) {
      if (item?.kind !== 'toolInvocationSerialized') continue;
      const subId = item.subAgentInvocationId;
      const owner =
        subId && launchById.has(subId)
          ? launchById.get(subId)
          : { name: orchName, model: orchModel };
      const toolId = item.toolId ?? '(unknown)';
      bumpAgent(owner.name, owner.model, 'toolCalls');
      bumpTool(owner.name, toolId);
    }
  }

  // Order: orchestrator rows first, then by tool calls desc, then by name.
  const agentRows = [...agents.values()].sort((a, b) => {
    if (a.name === orchName && b.name !== orchName) return -1;
    if (b.name === orchName && a.name !== orchName) return 1;
    return b.toolCalls - a.toolCalls || a.name.localeCompare(b.name);
  });

  // Tools grouped by agent in agentRows order, then by count desc.
  const agentOrder = new Map();
  for (const a of agentRows) {
    if (!agentOrder.has(a.name)) agentOrder.set(a.name, agentOrder.size);
  }
  const toolRows = [...tools.values()].sort((a, b) => {
    const ai = agentOrder.get(a.agent) ?? Infinity;
    const bi = agentOrder.get(b.agent) ?? Infinity;
    return ai - bi || b.count - a.count || a.tool.localeCompare(b.tool);
  });

  return {
    requestCount: reqs.length,
    slash,
    taskRef,
    start,
    end,
    durationMs: end - start,
    waitMs: totalWait,
    orchName,
    cost: computeCost(reqs),
    agentRows,
    toolRows,
    hasSubagents: agentRows.some((a) => a.name !== orchName),
  };
}

/**
 * Render rows as aligned columns.
 *
 * @template T
 * @param {T[]} rows
 * @param {Array<{ value: (row: T) => string, align?: 'left' | 'right', minWidth?: number }>} columns
 * @param {{ indent?: string, gap?: string, header?: string[], total?: string[], minRuleWidth?: number }} [opts]
 */
function renderTable(rows, columns, opts = {}) {
  const indent = opts.indent ?? '  ';
  const gap = opts.gap ?? '  ';

  const rendered = rows.map((r) => columns.map((col) => col.value(r)));

  const widths = columns.map((col, i) => {
    const headerLen = opts.header?.[i]?.length ?? 0;
    const totalLen = opts.total?.[i]?.length ?? 0;
    const rowLen = rendered.length
      ? Math.max(...rendered.map((r) => r[i]?.length ?? 0))
      : 0;
    return Math.max(col.minWidth ?? 0, headerLen, rowLen, totalLen);
  });

  // Expand the last left-aligned column to reach minRuleWidth, used to sync
  // sibling tables to the same total width.
  if (opts.minRuleWidth) {
    const currentW = widths.reduce((s, w, i) => s + w + (i > 0 ? gap.length : 0), 0);
    if (currentW < opts.minRuleWidth) {
      const deficit = opts.minRuleWidth - currentW;
      for (let i = columns.length - 1; i >= 0; i--) {
        if (columns[i].align !== 'right') {
          widths[i] += deficit;
          break;
        }
      }
    }
  }

  const padCell = (val, i) =>
    columns[i].align === 'right' ? val.padStart(widths[i]) : val.padEnd(widths[i]);

  // The final left-aligned cell needs no trailing padding (nothing follows
  // it on the line); right-aligned cells always pad because their leading
  // whitespace is structural.
  const renderRow = (cells) =>
    indent +
    cells
      .map((c, i) => {
        const v = c ?? '';
        const isLast = i === cells.length - 1;
        return isLast && columns[i].align !== 'right' ? v : padCell(v, i);
      })
      .join(gap);

  const lines = [];

  if (opts.header && opts.header.some((h) => h.length > 0)) {
    lines.push(renderRow(opts.header));
  }
  for (const row of rendered) {
    lines.push(renderRow(row));
  }
  if (opts.total) {
    const ruleW = widths.reduce((s, w, i) => s + w + (i > 0 ? gap.length : 0), 0);
    lines.push(indent + '─'.repeat(ruleW));
    lines.push(renderRow(opts.total));
  }

  return lines.join('\n');
}

/** Count the `─` characters on a rendered table's rule line. */
function measureRuleWidth(tableText) {
  for (const line of tableText.split('\n')) {
    const trimmed = line.replace(/^ +/, '');
    if (trimmed.startsWith('─')) {
      return [...trimmed].filter((c) => c === '─').length;
    }
  }
  return 0;
}

/** One-line Cost value, with `~` prefix when input estimated or unpriced. */
function renderCostValue(cost, requestCount) {
  const allUnpriced = cost.unpricedCount === requestCount && cost.unpricedCount > 0;
  if (allUnpriced) return `${DASH}  ${SEP}  ${DASH}`;
  const prefix = cost.inputEstimated || cost.unpricedCount > 0 ? '~' : '';
  return `${prefix}${fmtUsd(cost.usdTotal)}  ${SEP}  ${prefix}${fmtCredits(cost.creditsTotal)} AI credits`;
}

function renderTokens(cost) {
  const rows = [
    { cat: 'input', count: fmtInt(cost.inputTotal), prov: cost.inputEstimated ? 'estimated' : 'exact' },
    { cat: 'output', count: fmtInt(cost.outputTotal), prov: 'exact' },
    { cat: 'cache', count: DASH, prov: 'not persisted' },
  ];
  return renderTable(rows, [
    { value: (r) => r.cat, align: 'left' },
    { value: (r) => r.count, align: 'right' },
    { value: (r) => r.prov, align: 'left' },
  ]);
}

function renderAgents(rows, minRuleWidth) {
  const data = rows.map((a) => ({
    name: a.name,
    model: a.model || DASH,
    launches: fmtInt(a.launches),
    toolCalls: fmtInt(a.toolCalls),
  }));
  const totalLaunches = rows.reduce((s, a) => s + a.launches, 0);
  const totalCalls = rows.reduce((s, a) => s + a.toolCalls, 0);
  return renderTable(
    data,
    [
      { value: (r) => r.name, align: 'left' },
      { value: (r) => r.model, align: 'left' },
      { value: (r) => r.launches, align: 'right' },
      { value: (r) => r.toolCalls, align: 'right' },
    ],
    {
      header: ['', 'model', 'launches', 'tool calls'],
      total: ['total', '', fmtInt(totalLaunches), fmtInt(totalCalls)],
      minRuleWidth,
    },
  );
}

function renderTools(rows, minRuleWidth) {
  const data = rows.map((t) => ({
    agent: t.agent,
    tool: t.tool,
    count: fmtInt(t.count),
  }));
  const total = rows.reduce((s, t) => s + t.count, 0);
  return renderTable(
    data,
    [
      { value: (r) => r.agent, align: 'left' },
      { value: (r) => r.tool, align: 'left' },
      { value: (r) => r.count, align: 'right' },
    ],
    {
      header: ['', 'tool', 'calls'],
      total: ['total', '', fmtInt(total)],
      minRuleWidth,
    },
  );
}

function buildCaveats(s) {
  const parts = [];

  if (s.cost.inputEstimated) {
    parts.push(
      'Input is an upper-bound estimate. Agentic chats reship the ' +
        'conversation on every tool-call round, summed across rounds. ' +
        'VS Code does not expose prompt-cache hits — actual billed input ' +
        'may be substantially lower.',
    );
  }

  if (s.hasSubagents) {
    parts.push(
      "Subagent token usage is rolled into the orchestrator's request and " +
        "priced at the orchestrator's rate; if subagents ran on a different " +
        'model, the figure above diverges from the true cost.',
    );
  }

  if (s.cost.unpricedCount > 0) {
    const word = s.cost.unpricedCount === 1 ? 'request' : 'requests';
    parts.push(
      `Cost excludes ${s.cost.unpricedCount} ${word} with no priced rate ` +
        `(${s.cost.unpricedModels.join(', ')}).`,
    );
  }

  return parts
    .map((p) => wrap(p, WRAP_WIDTH).map((line) => `  ${line}`).join('\n'))
    .join('\n\n');
}

/**
 * @param {ReturnType<typeof analyze>} s
 * @param {string} fileLabel
 */
function render(s, fileLabel) {
  if (!s) return '';

  const out = [];

  out.push(`Chat report ${SEP} ${fmtDate(Date.now())}`);
  out.push('');
  out.push('');

  out.push(`  ${fileLabel}`);
  const ctx = [];
  if (s.taskRef) ctx.push(s.taskRef);
  if (s.slash) ctx.push('/' + s.slash);
  ctx.push(fmtPeriod(s.start, s.end));
  ctx.push(fmtDuration(s.durationMs));
  out.push(`  ${ctx.join(`  ${SEP}  `)}`);
  out.push('');
  out.push('');

  out.push('Cost');
  out.push(`  ${renderCostValue(s.cost, s.requestCount)}`);
  out.push('');

  out.push('Tokens');
  out.push(renderTokens(s.cost));
  out.push('');

  // Sync Agents and Tools to the same rule width: render once to measure,
  // re-render the narrower with explicit minRuleWidth.
  let agentsBlock = renderAgents(s.agentRows);
  let toolsBlock = s.toolRows.length > 0 ? renderTools(s.toolRows) : null;
  if (toolsBlock) {
    const agentsW = measureRuleWidth(agentsBlock);
    const toolsW = measureRuleWidth(toolsBlock);
    const target = Math.max(agentsW, toolsW);
    if (agentsW < target) agentsBlock = renderAgents(s.agentRows, target);
    if (toolsW < target) toolsBlock = renderTools(s.toolRows, target);
  }

  out.push('Agents');
  out.push(agentsBlock);
  out.push('');

  if (toolsBlock) {
    out.push('Tools');
    out.push(toolsBlock);
  }

  const caveats = buildCaveats(s);
  if (caveats) {
    out.push('');
    out.push('');
    out.push(caveats);
  }

  // Collapse runs of 3+ blank lines (from conditionally skipped sections)
  // down to 2, then trim trailing blanks.
  return out.join('\n').replace(/\n{4,}/g, '\n\n\n').replace(/\n+$/, '');
}

const inputPath = parseCliArgs();

let chat;
try {
  chat = JSON.parse(await readFile(inputPath, 'utf8'));
} catch (err) {
  log.error(err instanceof SyntaxError ? `Invalid JSON: ${err.message}` : err.message);
  process.exit(1);
}

const stats = analyze(chat);
if (!stats) {
  log.error('No requests found in chat dump.');
  process.exit(1);
}

log.info(render(stats, basename(inputPath)));
