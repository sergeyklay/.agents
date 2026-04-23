#!/usr/bin/env node
/**
 * analyze-chat-dump — Reports statistics for a VS Code Copilot Chat export.
 *
 * Reads a chat-session JSON dump and prints:
 *   - Session:    model(s), request count, slash command, task reference
 *   - Timeline:   start/end time (local), total duration, confirmation wait
 *   - Tokens:     input (prompt) and output (completion) totals
 *   - Subagents:  per-agent invocation counts
 *   - Tools:      per-tool invocation counts
 *
 * Usage:  node scripts/analyze-chat-dump.mjs <path-to-chat.json>
 *
 * Color output is enabled automatically when stdout is a TTY; it honors the
 * NO_COLOR and FORCE_COLOR environment variables.
 *
 * Schema references:
 *   - VS Code core: microsoft/vscode
 *     src/vs/workbench/contrib/chat/common/model/chatModel.ts
 *     ISerializableChatRequestData / ISerializableChatResponseData
 *     (timestamp, elapsedMs, timeSpentWaiting, completionTokens, message.parts).
 *   - Copilot Chat: microsoft/vscode-copilot-chat
 *     src/extension/intents/node/toolCallingLoop.ts — writes
 *     result.metadata.promptTokens / outputTokens via
 *     AnthropicTokenUsageMetadata; present only for Anthropic-family models,
 *     and reflects the LAST round of the request (not cumulative).
 *
 * Consequence: we report completionTokens as the authoritative output total
 * (accumulated by chatModel.ts across all tool-call rounds) and promptTokens
 * from result.metadata when available (Claude etc.), flagging partial
 * coverage when some requests used a non-Anthropic model like GPT-5.
 *
 * Per-subagent tokens: as of April 2026 the Copilot subagent serializer
 * (microsoft/vscode `searchSubagentTool.ts` / `executionSubagentToolCallingLoop.ts`)
 * does NOT persist token usage on the subagent record. The subagent's cost is
 * rolled into the request-level completionTokens accumulator. We still scan
 * for plausible token fields defensively so the script surfaces them for
 * free if the schema gains them later.
 */
import { readFile } from 'node:fs/promises';
import { basename, extname } from 'node:path';
import { parseArgs } from 'node:util';

// ---------------------------------------------------------------------------
// Logger — errors → stderr, output → stdout
// ---------------------------------------------------------------------------

const log = {
  info: (...a) => process.stdout.write(a.join(' ') + '\n'),
  error: (...a) => process.stderr.write('error: ' + a.join(' ') + '\n'),
};

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Color — auto-enable on TTY, respect NO_COLOR / FORCE_COLOR
// ---------------------------------------------------------------------------

// NO_COLOR always wins (https://no-color.org/). Otherwise FORCE_COLOR forces
// colors on; otherwise auto-detect via stdout TTY.
const SUPPORTS_COLOR = process.env.NO_COLOR
  ? false
  : process.env.FORCE_COLOR
    ? true
    : !!process.stdout.isTTY;

const ansi = (open, close) =>
  SUPPORTS_COLOR
    ? (/** @type {string} */ s) => `\x1b[${open}m${s}\x1b[${close}m`
    : (/** @type {string} */ s) => s;

// Palette — three roles only:
//   level1 → main section headers (Chat statistics, Session, Timeline, …)
//   level2 → sub-block headers (Orchestrator, Coder, Architect, …)
//   dim    → parenthetical notes only, nothing else
// Everything else renders in the terminal's default foreground (white).
const c = {
  level1: ansi('1;36', '22;39'), // bold cyan
  level2: ansi('1;33', '22;39'), // bold yellow
  dim: ansi(2, 22),
};

const DASH = '—';

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

const MS_PER_MINUTE = 60_000;
const LABEL_WIDTH = 11;
const MIN_TOOL_ID_WIDTH = 20;
const MAX_TASK_FALLBACK = 72;

/** @param {number} ms */
function fmtDuration(ms) {
  const totalMin = Math.floor(ms / MS_PER_MINUTE);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return `${h}h ${m}m`;
}

/**
 * Format a millisecond timestamp as `YYYY-MM-DD HH:MM:SS` in the system's
 * local timezone. Locale-independent, unambiguous.
 *
 * @param {number} ms
 */
function fmtLocal(ms) {
  const d = new Date(ms);
  const pad = (/** @type {number} */ n) => String(n).padStart(2, '0');
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  );
}

/** @param {number} n */
function fmtInt(n) {
  return n.toLocaleString('en-US');
}

/** @param {string} label @param {string} value */
function kv(label, value) {
  return `  ${label.padEnd(LABEL_WIDTH)}${value}`;
}

// ---------------------------------------------------------------------------
// Analysis
// ---------------------------------------------------------------------------

/**
 * Guard against a historical VS Code bug where `timeSpentWaiting` was
 * serialized as the absolute wait-start timestamp instead of a duration.
 * If the value is not smaller than the request's own start timestamp,
 * it cannot be a valid duration within that request.
 *
 * @param {{ timestamp?: number, timeSpentWaiting?: number }} req
 */
function sanitizedWait(req) {
  const w = req.timeSpentWaiting ?? 0;
  const ts = req.timestamp ?? 0;
  return ts > 0 && w >= ts ? 0 : w;
}

/**
 * Slash commands live in `message.parts[].kind === 'prompt'`, with the
 * command name (minus the leading slash) in `.name`.
 *
 * @param {any} req
 */
function extractSlashCommand(req) {
  const parts = req?.message?.parts ?? [];
  const prompt = parts.find((/** @type {any} */ p) => p?.kind === 'prompt');
  return prompt?.name ?? null;
}

/**
 * Extract a task reference from the first user message and its attachments.
 * Strategy:
 *   1. Collect every `BP-\d+` identifier from the message text and from
 *      attachment names in variableData (e.g. `Spec-BP-247.md`).
 *   2. If found → return comma-joined sorted list.
 *   3. Else → fall back to the slash-command argument (trimmed, truncated).
 *   4. Else → return null.
 *
 * @param {any} req
 * @param {string | null} slash
 */
function extractTaskRef(req, slash) {
  const ids = new Set();
  const text = req?.message?.text ?? '';
  // Case-insensitive because attachment names sometimes use "Spec-bp-96.md".
  // Normalize every match to uppercase so `bp-96` and `BP-96` dedup.
  const BP_RE = /\bBP-\d+\b/gi;
  for (const m of text.matchAll(BP_RE)) ids.add(m[0].toUpperCase());

  const vars = req?.variableData?.variables ?? [];
  for (const v of vars) {
    const name = v?.name ?? '';
    for (const m of name.matchAll(BP_RE)) ids.add(m[0].toUpperCase());
  }

  if (ids.size > 0) {
    return [...ids]
      .sort((a, b) => {
        const na = Number(a.slice(3));
        const nb = Number(b.slice(3));
        return na - nb;
      })
      .join(', ');
  }

  // Fallback: slash-command argument on the first line
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
 * Defensively pull per-subagent token usage out of any field VS Code might
 * use now or in the future. As of April 2026, the VS Code / Copilot Chat
 * subagent serialization does not persist token counts (verified against
 * microsoft/vscode `searchSubagentTool.ts` and `executionSubagentToolCallingLoop.ts`),
 * so in all current dumps this returns `{ input: null, output: null }`.
 * If the schema ever gains token fields, they show up without a code change.
 *
 * @param {any} tsd   toolSpecificData for a subagent invocation
 * @param {any} item  the enclosing toolInvocationSerialized entry
 * @returns {{ input: number | null, output: number | null }}
 */
function extractSubagentTokens(tsd, item) {
  const pickInt = (/** @type {any} */ v) =>
    typeof v === 'number' && Number.isFinite(v) ? v : null;

  const input =
    pickInt(tsd?.promptTokens) ??
    pickInt(tsd?.inputTokens) ??
    pickInt(tsd?.usage?.prompt_tokens) ??
    pickInt(tsd?.usage?.promptTokens) ??
    pickInt(item?.promptTokens) ??
    pickInt(item?.usage?.prompt_tokens);

  const output =
    pickInt(tsd?.completionTokens) ??
    pickInt(tsd?.outputTokens) ??
    pickInt(tsd?.usage?.completion_tokens) ??
    pickInt(tsd?.usage?.completionTokens) ??
    pickInt(item?.completionTokens) ??
    pickInt(item?.usage?.completion_tokens);

  return { input, output };
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

  let completionTotal = 0;
  let promptMdTotal = 0;
  let reqsWithPromptMd = 0;
  let totalWait = 0;

  // Subagent launches:
  //   `runSubagent` tool invocations carry `toolSpecificData.kind === 'subagent'`
  //   with the spawned agent's `agentName` and `modelName`. Each launch has its
  //   own `toolCallId`, which nested tool invocations reference via
  //   `subAgentInvocationId` — this is how we attribute internal tool calls to
  //   the subagent that made them (vs the orchestrator).

  /** @type {Map<string, { agentName: string, modelName: string | null }>} */
  const subagentById = new Map();

  /** @type {Map<string, { count: number, models: Set<string>, inputTokens: number | null, outputTokens: number | null }>} */
  const subagentLaunches = new Map();

  const ORCH = 'Orchestrator';

  /** @type {Map<string, { name: string, models: Set<string>, tools: Map<string, { count: number, source: string }>, totalCalls: number }>} */
  const owners = new Map();
  owners.set(ORCH, { name: ORCH, models: new Set(), tools: new Map(), totalCalls: 0 });

  const getOwner = (/** @type {string} */ key) => {
    let o = owners.get(key);
    if (!o) {
      o = { name: key, models: new Set(), tools: new Map(), totalCalls: 0 };
      owners.set(key, o);
    }
    return o;
  };

  for (const r of reqs) {
    completionTotal += r.completionTokens ?? 0;
    totalWait += sanitizedWait(r);
    if (r.modelId) owners.get(ORCH).models.add(r.modelId);

    const md = r.result?.metadata;
    if (md?.promptTokens != null) {
      promptMdTotal += md.promptTokens;
      reqsWithPromptMd += 1;
    }

    const resp = Array.isArray(r.response) ? r.response : [];

    // Pass 1 — register every subagent launch so nested items can resolve.
    for (const item of resp) {
      if (item?.kind !== 'toolInvocationSerialized') continue;
      const tsd = item.toolSpecificData;
      if (tsd?.kind !== 'subagent') continue;
      const name = tsd.agentName || '(ad-hoc)';
      const modelName = tsd.modelName || null;
      if (item.toolCallId) subagentById.set(item.toolCallId, { agentName: name, modelName });
      const launch = subagentLaunches.get(name) ?? {
        count: 0,
        models: new Set(),
        inputTokens: null,
        outputTokens: null,
      };
      launch.count += 1;
      if (modelName) launch.models.add(modelName);
      const { input, output } = extractSubagentTokens(tsd, item);
      if (input != null) launch.inputTokens = (launch.inputTokens ?? 0) + input;
      if (output != null) launch.outputTokens = (launch.outputTokens ?? 0) + output;
      subagentLaunches.set(name, launch);
    }

    // Pass 2 — attribute each tool invocation to its owner.
    for (const item of resp) {
      if (item?.kind !== 'toolInvocationSerialized') continue;

      const subId = item.subAgentInvocationId;
      let ownerKey = ORCH;
      if (subId) {
        const sub = subagentById.get(subId);
        ownerKey = sub?.agentName ?? '(ad-hoc)';
        if (sub?.modelName) getOwner(ownerKey).models.add(sub.modelName);
      }

      const owner = getOwner(ownerKey);
      const id = item.toolId ?? '(unknown)';
      const source = item.source?.label ?? item.source?.type ?? '';
      const cur = owner.tools.get(id) ?? { count: 0, source };
      cur.count += 1;
      owner.tools.set(id, cur);
      owner.totalCalls += 1;
    }
  }

  // Owner blocks: Orchestrator first, then subagents ranked by call count.
  const ownerBlocks = [...owners.values()]
    .filter((o) => o.totalCalls > 0)
    .map((o) => ({
      name: o.name,
      models: [...o.models].sort(),
      totalCalls: o.totalCalls,
      tools: [...o.tools.entries()]
        .map(([id, { count, source }]) => ({ id, count, source }))
        .sort((a, b) => b.count - a.count || a.id.localeCompare(b.id)),
    }))
    .sort((a, b) => {
      if (a.name === ORCH) return -1;
      if (b.name === ORCH) return 1;
      return b.totalCalls - a.totalCalls || a.name.localeCompare(b.name);
    });

  const totalToolCalls = ownerBlocks.reduce((s, b) => s + b.totalCalls, 0);

  const subagentRows = [...subagentLaunches.entries()]
    .map(([name, { count, models, inputTokens, outputTokens }]) => ({
      name,
      count,
      models: [...models].sort(),
      inputTokens,
      outputTokens,
    }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  const totalSubagentLaunches = subagentRows.reduce((s, r) => s + r.count, 0);
  const anySubagentTokens = subagentRows.some(
    (r) => r.inputTokens != null || r.outputTokens != null,
  );

  return {
    requestCount: reqs.length,
    orchestratorModels: [...owners.get(ORCH).models].sort(),
    slash,
    taskRef,
    start,
    end,
    durationMs: end - start,
    waitMs: totalWait,
    completionTotal,
    promptMdTotal,
    promptCoverage: { covered: reqsWithPromptMd, total: reqs.length },
    totalToolCalls,
    ownerBlocks,
    totalSubagentLaunches,
    subagentRows,
    anySubagentTokens,
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/**
 * @param {ReturnType<typeof analyze>} s
 * @param {string} fileLabel
 */
function render(s, fileLabel) {
  if (!s) return '';

  // Source tags render as dim parentheticals ("(snyk)"), per the palette rule
  // that grey is reserved for parenthetical notes only.
  const fmtSource = (/** @type {string} */ source) =>
    source && source !== 'Built-In' ? `   ${c.dim(`(${source})`)}` : '';

  // Composite label for a subagent row — same `name  ·  model` shape Tools
  // uses in its sub-block headers, so Subagents reads as one of that family.
  const composite = (/** @type {{ name: string, models: string[] }} */ r) =>
    `${r.name}  ·  ${r.models.join(', ') || DASH}`;

  // Global count-column alignment.
  // Subagent rows render at indent 2 (peers of a section header); Tools tool
  // rows render at indent 4 (nested under a sub-block header). We want the
  // count column to land at the same visual column in both, so every row's
  // "indent + first-column width" must resolve to the same total.
  const SUBAGENT_INDENT = 2;
  const TOOL_ROW_INDENT = 4;

  const allCounts = [
    ...s.subagentRows.map((r) => r.count),
    ...s.ownerBlocks.flatMap((b) => b.tools.map((t) => t.count)),
  ];
  const countW = String(Math.max(1, ...allCounts)).length;

  const firstColTotals = [
    // MIN keeps the column legible even when every tool name is short.
    TOOL_ROW_INDENT + MIN_TOOL_ID_WIDTH,
    ...s.subagentRows.map((r) => SUBAGENT_INDENT + composite(r).length),
    ...s.ownerBlocks.flatMap((b) => b.tools.map((t) => TOOL_ROW_INDENT + t.id.length)),
  ];
  const firstColMax = Math.max(1, ...firstColTotals);
  const compW = firstColMax - SUBAGENT_INDENT;
  const idW = firstColMax - TOOL_ROW_INDENT;

  const out = [];
  out.push(`${c.level1('Chat statistics')}  —  ${fileLabel}`);
  out.push('');

  // Session ---------------------------------------------------------------
  out.push(c.level1('Session'));
  const orchLabel = s.orchestratorModels.length > 1 ? 'Models' : 'Model';
  out.push(kv(orchLabel, s.orchestratorModels.join(', ') || c.dim('(unspecified)')));
  out.push(kv('Requests', String(s.requestCount)));
  out.push(kv('Command', s.slash ? '/' + s.slash : DASH));
  out.push(kv('Task', s.taskRef ?? DASH));
  out.push('');

  // Timeline --------------------------------------------------------------
  const durMin = Math.round(s.durationMs / MS_PER_MINUTE);
  out.push(c.level1('Timeline'));
  out.push(kv('Started', fmtLocal(s.start)));
  out.push(kv('Ended', fmtLocal(s.end)));
  out.push(kv('Duration', `${fmtDuration(s.durationMs)}  ${c.dim(`(${fmtInt(durMin)} min)`)}`));
  if (s.waitMs >= MS_PER_MINUTE) {
    out.push(kv('Waiting', `${fmtDuration(s.waitMs)}  ${c.dim('(confirmation prompts)')}`));
  }
  out.push('');

  // Tokens ----------------------------------------------------------------
  out.push(c.level1('Tokens'));
  if (s.promptCoverage.covered === 0) {
    out.push(kv('Input', `${DASH}  ${c.dim('(non-Anthropic model; not persisted by VS Code)')}`));
  } else {
    const partial =
      s.promptCoverage.covered < s.promptCoverage.total
        ? `  ${c.dim(`(partial: ${s.promptCoverage.covered} of ${s.promptCoverage.total} requests had Anthropic metadata)`)}`
        : '';
    out.push(kv('Input', `${fmtInt(s.promptMdTotal)}${partial}`));
  }
  out.push(kv('Output', fmtInt(s.completionTotal)));
  out.push('');

  // Subagents -------------------------------------------------------------
  if (s.subagentRows.length > 0) {
    out.push(
      c.level1('Subagents') +
        `  ${c.dim(`(${s.totalSubagentLaunches} launches, ${s.subagentRows.length} distinct)`)}`,
    );

    if (s.anySubagentTokens) {
      // Token columns: right-aligned, sized to the widest formatted number.
      // With tokens present the row is no longer a simple 2-column table, so
      // it keeps its own alignment — the global count column does not apply.
      const fmtTok = (/** @type {number | null} */ v) => (v == null ? DASH : fmtInt(v));
      const inW = Math.max(5, ...s.subagentRows.map((r) => fmtTok(r.inputTokens).length));
      const outW = Math.max(6, ...s.subagentRows.map((r) => fmtTok(r.outputTokens).length));
      out.push(
        `  ${''.padEnd(compW)}  ${''.padStart(countW)}  ${c.dim('input'.padStart(inW))}  ${c.dim('output'.padStart(outW))}`,
      );
      for (const r of s.subagentRows) {
        const inCol = fmtTok(r.inputTokens).padStart(inW);
        const outCol = fmtTok(r.outputTokens).padStart(outW);
        out.push(
          `  ${composite(r).padEnd(compW)}  ${String(r.count).padStart(countW)}  ${inCol}  ${outCol}`,
        );
      }
    } else {
      for (const r of s.subagentRows) {
        out.push(`  ${composite(r).padEnd(compW)}  ${String(r.count).padStart(countW)}`);
      }
    }
    out.push('');
  }

  // Tools -----------------------------------------------------------------
  if (s.ownerBlocks.length === 0) {
    out.push(c.level1('Tools') + `  ${c.dim('(0 calls)')}`);
    out.push(`  ${c.dim('(none used)')}`);
    return out.join('\n');
  }

  // Flat layout when only the orchestrator used tools. Tool rows render at
  // indent 2 (same as Subagents rows) so we use `compW` — the Subagents-side
  // first-column width — to keep the count column aligned with Subagents.
  if (s.ownerBlocks.length === 1 && s.ownerBlocks[0].name === 'Orchestrator') {
    const block = s.ownerBlocks[0];
    out.push(
      c.level1('Tools') +
        `  ${c.dim(`(${block.totalCalls} calls, ${block.tools.length} distinct)`)}`,
    );
    for (const { id, count, source } of block.tools) {
      out.push(`  ${id.padEnd(compW)}  ${String(count).padStart(countW)}${fmtSource(source)}`);
    }
    return out.join('\n');
  }

  // Split layout: one sub-block per actor. Tool-ID column is sized per block,
  // so short blocks (e.g. Orchestrator, Planner) stay compact while wide tool
  // names only stretch the blocks that contain them.
  const actors = s.ownerBlocks.length;
  out.push(
    c.level1('Tools') +
      `  ${c.dim(`(${s.totalToolCalls} calls across ${actors} actor${actors === 1 ? '' : 's'})`)}`,
  );

  for (const block of s.ownerBlocks) {
    out.push('');
    const head =
      block.models.length > 0 && block.name !== 'Orchestrator'
        ? c.level2(`${block.name}  ·  ${block.models.join(', ')}`)
        : c.level2(block.name);
    out.push(`  ${head}  ${c.dim(`(${block.totalCalls} calls, ${block.tools.length} distinct)`)}`);
    for (const { id, count, source } of block.tools) {
      out.push(`    ${id.padEnd(idW)}  ${String(count).padStart(countW)}${fmtSource(source)}`);
    }
  }

  return out.join('\n');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

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
