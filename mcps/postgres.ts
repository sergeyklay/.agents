#!/usr/bin/env node
/**
 * PostgreSQL MCP Server
 *
 * A read-only, fully-discoverable Model Context Protocol server for
 * PostgreSQL. Uses all three MCP primitives:
 *
 *   Resources - schema metadata the LLM reads as grounding context
 *   Tools     - safe query execution and schema search driven by the model
 *   Prompts   - reusable templates that guide structured exploration
 *
 * Safety model (layered defence):
 *   1. Session-level - SET default_transaction_read_only = on per connection
 *   2. Timeout-level - statement_timeout (default 30 s) + lock_timeout (5 s)
 *   3. App-level     - SQL keyword validation before any execution
 *   4. Result-level  - hard row cap injected when LIMIT is absent
 *
 * Usage:
 *   DATABASE_URL=postgresql://user:pass@host:port/dbname \
 *     npx tsx .github/mcps/postgres.ts
 *
 * Environment variables:
 *   DATABASE_URL             Connection string (also accepts DATABASE_URI).
 *                            If not set, the server reads .env.local then .env
 *                            from the project root automatically.
 *   MCP_POOL_MIN             Min pool connections (default: 1)
 *   MCP_POOL_MAX             Max pool connections (default: 5)
 *   MCP_STATEMENT_TIMEOUT    Statement timeout ms (default: 30000)
 *   MCP_ROW_LIMIT            Max rows per query (default: 500)
 *   MCP_SCHEMA_CACHE_TTL_MS  Heavy-resource cache TTL (default: 300000 / 5 min)
 *                            Used for catalog and per-table DDL.
 *   MCP_LIST_CACHE_TTL_MS    Resource-list cache TTL (default: 60000 / 1 min)
 *                            Shorter - DDL changes (migrations) propagate sooner.
 *   MCP_DEBUG                Verbose stderr logs (set to "1")
 */
import os from "node:os";
import path from "node:path";
import process from "node:process";
import {
    McpServer,
    ResourceTemplate,
} from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { config as dotenvConfig } from "dotenv";
import { Pool } from "pg";
import { z } from "zod";

import type { PoolClient } from "pg";

// ── .env fallback ──────────────────────────────────────────────────────────────
// Load .env files from the project root so DATABASE_URL can be omitted from
// mcp.json. Loaded in priority order - first file wins, and any variable
// already set in the process environment (e.g. via mcp.json "env" block) is
// never overwritten (dotenv's default override: false behaviour).
//
// __dirname is scripts/mcps/ - two levels up is the project root.
const _projectRoot = path.resolve(__dirname, "..", "..");
for (const file of [".env.local", ".env"]) {
    dotenvConfig({ path: path.join(_projectRoot, file), override: false });
}

// ── Configuration ─────────────────────────────────────────────────────────────

const DATABASE_URL =
    process.env["DATABASE_URL"] ?? process.env["DATABASE_URI"] ?? "";
const POOL_MIN = Number(process.env["MCP_POOL_MIN"] ?? "1");
const POOL_MAX = Number(process.env["MCP_POOL_MAX"] ?? "5");
const STATEMENT_TIMEOUT_MS = Number(
    process.env["MCP_STATEMENT_TIMEOUT"] ?? "30000",
);
const ROW_LIMIT = Number(process.env["MCP_ROW_LIMIT"] ?? "500");
const SCHEMA_CACHE_TTL_MS = Number(
    process.env["MCP_SCHEMA_CACHE_TTL_MS"] ?? "300000",
);
const LIST_CACHE_TTL_MS = Number(
    process.env["MCP_LIST_CACHE_TTL_MS"] ?? "60000",
);
const DEBUG = process.env["MCP_DEBUG"] === "1";

if (!DATABASE_URL) {
    process.stderr.write(
        "[FATAL] DATABASE_URL (or DATABASE_URI) must be set.\n" +
            "  Example: DATABASE_URL=postgresql://user:pass@localhost:5432/mydb npx tsx .github/mcps/postgres.ts\n",
    );
    process.exit(1);
}

// ── Logging (stderr only - stdout is owned by the MCP stdio transport) ────────

function logInfo(msg: string): void {
    process.stderr.write(`[INFO]  ${msg}\n`);
}
function logError(msg: string, err?: unknown): void {
    const detail = err !== undefined ? ` - ${String(err)}` : "";
    process.stderr.write(`[ERROR] ${msg}${detail}\n`);
}
function logDebug(msg: string): void {
    if (DEBUG) process.stderr.write(`[DEBUG] ${msg}\n`);
}

/** Returns a display-safe version of a connection string (password redacted). */
function safeUrl(raw: string): string {
    try {
        const u = new URL(raw);
        if (u.password) u.password = "*****";
        return u.toString();
    } catch {
        return "[connection string redacted]";
    }
}

// ── Database pool ──────────────────────────────────────────────────────────────

const pool = new Pool({
    connectionString: DATABASE_URL,
    min: POOL_MIN,
    max: POOL_MAX,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
});

pool.on("error", (err) => logError("Idle pool client error", err));

/**
 * Acquire a connection from the pool, harden its session to be read-only and
 * timeout-bounded, run `fn`, then release it unconditionally.
 *
 * Every operation flows through this helper - it is the single chokepoint for
 * both safety enforcement and connection lifecycle.
 */
async function withDb<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await pool.connect();
    try {
        // Layer 1: session-level read-only + timeout enforcement
        await client.query(`
      SET default_transaction_read_only = on;
      SET statement_timeout              = ${STATEMENT_TIMEOUT_MS};
      SET lock_timeout                   = 5000;
      SET idle_in_transaction_session_timeout = 10000;
    `);
        return await fn(client);
    } finally {
        client.release();
    }
}

// ── Schema cache ───────────────────────────────────────────────────────────────

interface CacheEntry<T> {
    readonly value: T;
    readonly expiresAt: number;
}

const _cache = new Map<string, CacheEntry<unknown>>();

function getCached<T>(key: string): T | undefined {
    const entry = _cache.get(key);
    if (!entry) {
        logDebug(`cache miss: ${key}`);
        return undefined;
    }
    if (Date.now() > entry.expiresAt) {
        _cache.delete(key);
        logDebug(`cache expired: ${key}`);
        return undefined;
    }
    logDebug(`cache hit: ${key}`);
    return entry.value as T;
}

function setCached<T>(
    key: string,
    value: T,
    ttlMs: number = SCHEMA_CACHE_TTL_MS,
): void {
    _cache.set(key, { value, expiresAt: Date.now() + ttlMs });
}

// ── SQL safety helpers ─────────────────────────────────────────────────────────

/** Keywords that indicate a read-only entry point for a statement. */
const READ_ENTRY_RE = /^\s*(SELECT|EXPLAIN|SHOW|WITH|TABLE\b|VALUES\b)/i;

/** Statements that are valid in a derived-table position for row-limit wrapping. */
const WRAPPABLE_RE = /^\s*(SELECT|WITH|VALUES)\b/i;

/** DML/DDL keywords that must not appear once strings and comments are masked. */
const MUTATING_RE =
    /\b(INSERT|UPDATE|DELETE|TRUNCATE|DROP|CREATE|ALTER|REPLACE|MERGE|UPSERT|GRANT|REVOKE|CALL|DO|COPY)\b/i;

/** Session-control keywords that must not appear once strings and comments are masked. */
const SESSION_CONTROL_RE =
    /\b(SET|RESET|BEGIN|COMMIT|ROLLBACK|LOCK|DISCARD|DEALLOCATE)\b/i;

const IDENTIFIER_START_RE = /[A-Za-z_]/;
const IDENTIFIER_PART_RE = /[A-Za-z0-9_]/;

function maskRange(
    masked: string[],
    sql: string,
    start: number,
    end: number,
): void {
    for (let index = start; index < end; index += 1) {
        masked[index] = sql[index] === "\n" ? "\n" : " ";
    }
}

function advancePastLineComment(
    sql: string,
    start: number,
): number | undefined {
    if (!sql.startsWith("--", start)) {
        return undefined;
    }

    let cursor = start + 2;
    while (cursor < sql.length && sql[cursor] !== "\n") {
        cursor += 1;
    }

    return cursor;
}

function advancePastBlockComment(
    sql: string,
    start: number,
): number | undefined {
    if (!sql.startsWith("/*", start)) {
        return undefined;
    }

    let cursor = start + 2;
    let depth = 1;

    while (cursor < sql.length && depth > 0) {
        if (sql.startsWith("/*", cursor)) {
            depth += 1;
            cursor += 2;
            continue;
        }

        if (sql.startsWith("*/", cursor)) {
            depth -= 1;
            cursor += 2;
            continue;
        }

        cursor += 1;
    }

    return cursor;
}

function readDollarQuoteTag(sql: string, start: number): string | undefined {
    if (sql[start] !== "$") {
        return undefined;
    }

    const secondChar = sql[start + 1];
    if (secondChar === "$") {
        return "$$";
    }

    if (!secondChar || !IDENTIFIER_START_RE.test(secondChar)) {
        return undefined;
    }

    let cursor = start + 2;
    while (cursor < sql.length && IDENTIFIER_PART_RE.test(sql[cursor] ?? "")) {
        cursor += 1;
    }

    return sql[cursor] === "$" ? sql.slice(start, cursor + 1) : undefined;
}

function advancePastDollarQuotedString(
    sql: string,
    start: number,
): number | undefined {
    const tag = readDollarQuoteTag(sql, start);
    if (!tag) {
        return undefined;
    }

    const contentStart = start + tag.length;
    const end = sql.indexOf(tag, contentStart);
    return end === -1 ? sql.length : end + tag.length;
}

function advancePastSingleQuotedLiteral(
    sql: string,
    start: number,
): number | undefined {
    if (sql[start] !== "'") {
        return undefined;
    }

    let cursor = start + 1;
    while (cursor < sql.length) {
        if (sql[cursor] === "\\" && cursor + 1 < sql.length) {
            cursor += 2;
            continue;
        }

        if (sql[cursor] === "'") {
            if (sql[cursor + 1] === "'") {
                cursor += 2;
                continue;
            }

            return cursor + 1;
        }

        cursor += 1;
    }

    return cursor;
}

function advancePastDoubleQuotedIdentifier(
    sql: string,
    start: number,
): number | undefined {
    if (sql[start] !== '"') {
        return undefined;
    }

    let cursor = start + 1;
    while (cursor < sql.length) {
        if (sql[cursor] === '"') {
            if (sql[cursor + 1] === '"') {
                cursor += 2;
                continue;
            }

            return cursor + 1;
        }

        cursor += 1;
    }

    return cursor;
}

function advancePastMaskedSection(
    sql: string,
    start: number,
): number | undefined {
    return (
        advancePastLineComment(sql, start) ??
        advancePastBlockComment(sql, start) ??
        advancePastDollarQuotedString(sql, start) ??
        advancePastSingleQuotedLiteral(sql, start) ??
        advancePastDoubleQuotedIdentifier(sql, start)
    );
}

/**
 * maskSqlForAnalysis blanks comments, quoted identifiers, and literals while
 * preserving statement structure for keyword and semicolon checks.
 */
function maskSqlForAnalysis(sql: string): string {
    const masked = [...sql];
    let cursor = 0;

    while (cursor < sql.length) {
        const sectionEnd = advancePastMaskedSection(sql, cursor);
        if (sectionEnd === undefined) {
            cursor += 1;
            continue;
        }

        maskRange(masked, sql, cursor, sectionEnd);
        cursor = sectionEnd;
    }

    return masked.join("");
}

function hasEmbeddedSemicolon(maskedSql: string): boolean {
    return maskedSql.replace(/;\s*$/, "").includes(";");
}

function hasExplicitOuterLimit(maskedSql: string): boolean {
    const lastParen = maskedSql.lastIndexOf(")");
    const tail = lastParen >= 0 ? maskedSql.slice(lastParen) : maskedSql;
    return /\bLIMIT\b/i.test(tail);
}

/**
 * validateReadOnly returns an error message when SQL is unsafe to execute.
 *
 * The validator rejects multi-statement SQL, requires a read-only entry
 * keyword, and blocks mutating or session-control keywords after masking SQL
 * comments, quoted identifiers, and literals.
 */
function validateReadOnly(sql: string): string | undefined {
    const maskedSql = maskSqlForAnalysis(sql).trim();

    if (hasEmbeddedSemicolon(maskedSql)) {
        return "Multi-statement SQL is not allowed. Submit one statement at a time.";
    }

    if (!READ_ENTRY_RE.test(maskedSql)) {
        return "Query must begin with SELECT, EXPLAIN, SHOW, WITH, TABLE, or VALUES.";
    }
    if (MUTATING_RE.test(maskedSql)) {
        return "Query contains a mutating keyword. This server is read-only.";
    }
    if (SESSION_CONTROL_RE.test(maskedSql)) {
        return "Session-control statements (SET, RESET, BEGIN, LOCK, etc.) are not allowed.";
    }

    return undefined;
}

/**
 * injectRowLimit wraps wrappable read-only queries in an outer LIMIT when needed.
 *
 * Comments, quoted identifiers, and literals are ignored when detecting an
 * existing outer LIMIT so harmless text such as `'limit 1'` does not suppress
 * the safety cap.
 */
function injectRowLimit(sql: string, limit: number): string {
    const maskedSql = maskSqlForAnalysis(sql).trim();

    if (!WRAPPABLE_RE.test(maskedSql)) {
        return sql;
    }
    if (hasExplicitOuterLimit(maskedSql)) {
        return sql;
    }

    return `SELECT * FROM (\n${sql}\n) AS _mcp_bounded LIMIT ${limit}`;
}

// ── Introspection types ────────────────────────────────────────────────────────

interface ColumnInfo {
    name: string;
    type: string;
    nullable: boolean;
    default: string | undefined;
    isPrimaryKey: boolean;
}

interface IndexInfo {
    name: string;
    columns: string[];
    isUnique: boolean;
    isPrimary: boolean;
    method: string;
}

interface ForeignKeyInfo {
    column: string;
    referencesSchema: string;
    referencesTable: string;
    referencesColumn: string;
    onDelete: string;
}

interface IncomingRefInfo {
    fromSchema: string;
    fromTable: string;
    fromColumn: string;
}

interface TableDefinition {
    schema: string;
    table: string;
    isView: boolean;
    rowEstimate: number;
    columns: ColumnInfo[];
    indexes: IndexInfo[];
    foreignKeys: ForeignKeyInfo[];
    incomingRefs: IncomingRefInfo[];
}

interface CatalogColumn {
    name: string;
    type: string;
    pk?: true;
}

interface CatalogForeignKey {
    col: string;
    ref: string; // "schema.table.column"
}

interface CatalogTable {
    schema: string;
    name: string;
    kind: "TABLE" | "VIEW";
    rows: number; // pg_stat estimate; -1 when the planner has no estimate yet
    columns: CatalogColumn[];
    fks: CatalogForeignKey[];
}

interface CatalogEnum {
    schema: string;
    name: string;
    values: string[];
}

interface Catalog {
    database: string;
    version: string;
    schemas: string[];
    tables: CatalogTable[];
    enums: CatalogEnum[];
}

// ── Introspection queries ──────────────────────────────────────────────────────

async function fetchTableDefinition(
    schema: string,
    table: string,
): Promise<TableDefinition> {
    const cacheKey = `table:${schema}.${table}`;
    const cached = getCached<TableDefinition>(cacheKey);
    if (cached) return cached;

    logDebug(`Fetching definition for ${schema}.${table}`);

    const definition = await withDb(async (client) => {
        // ── Columns with PK membership resolved in one pass ────────────────────
        const { rows: colRows } = await client.query<{
            name: string;
            type: string;
            nullable: string;
            default_val: string | null;
            is_pk: boolean;
        }>(
            `
      SELECT
        c.column_name                                                   AS name,
        CASE
          WHEN c.data_type = 'USER-DEFINED'        THEN c.udt_name
          WHEN c.character_maximum_length IS NOT NULL
            THEN c.data_type || '(' || c.character_maximum_length || ')'
          ELSE c.data_type
        END                                                             AS type,
        c.is_nullable                                                   AS nullable,
        c.column_default                                                AS default_val,
        EXISTS (
          SELECT 1
          FROM   information_schema.key_column_usage kcu
          JOIN   information_schema.table_constraints tc
                   ON  tc.constraint_name = kcu.constraint_name
                   AND tc.table_schema    = kcu.table_schema
          WHERE  tc.constraint_type = 'PRIMARY KEY'
            AND  kcu.table_schema   = c.table_schema
            AND  kcu.table_name     = c.table_name
            AND  kcu.column_name    = c.column_name
        )                                                               AS is_pk
      FROM   information_schema.columns c
      WHERE  c.table_schema = $1
        AND  c.table_name   = $2
      ORDER  BY c.ordinal_position
      `,
            [schema, table],
        );

        // ── Indexes via pg_catalog (richer than information_schema) ────────────
        const { rows: idxRows } = await client.query<{
            name: string;
            columns: string[];
            is_unique: boolean;
            is_primary: boolean;
            method: string;
        }>(
            `
      SELECT
        i.relname                                     AS name,
        array_agg(a.attname ORDER BY k.pos)           AS columns,
        ix.indisunique                                AS is_unique,
        ix.indisprimary                               AS is_primary,
        am.amname                                     AS method
      FROM   pg_class      t
      JOIN   pg_index      ix ON ix.indrelid  = t.oid
      JOIN   pg_class      i  ON i.oid        = ix.indexrelid
      JOIN   pg_am         am ON i.relam      = am.oid
      JOIN   pg_namespace  n  ON n.oid        = t.relnamespace
      CROSS  JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS k(attnum, pos)
      JOIN   pg_attribute  a  ON a.attrelid   = t.oid AND a.attnum = k.attnum
      WHERE  n.nspname = $1
        AND  t.relname = $2
        AND  a.attnum  > 0
      GROUP  BY i.relname, ix.indisunique, ix.indisprimary, am.amname
      ORDER  BY ix.indisprimary DESC, ix.indisunique DESC, i.relname
      `,
            [schema, table],
        );

        // ── Outgoing foreign keys ──────────────────────────────────────────────
        const { rows: fkRows } = await client.query<{
            column: string;
            ref_schema: string;
            ref_table: string;
            ref_column: string;
            on_delete: string;
        }>(
            `
      SELECT
        kcu.column_name   AS column,
        ccu.table_schema  AS ref_schema,
        ccu.table_name    AS ref_table,
        ccu.column_name   AS ref_column,
        rc.delete_rule    AS on_delete
      FROM   information_schema.table_constraints      tc
      JOIN   information_schema.key_column_usage       kcu
               ON  kcu.constraint_name = tc.constraint_name
               AND kcu.table_schema    = tc.table_schema
      JOIN   information_schema.constraint_column_usage ccu
               ON  ccu.constraint_name = tc.constraint_name
      JOIN   information_schema.referential_constraints rc
               ON  rc.constraint_name  = tc.constraint_name
      WHERE  tc.table_schema    = $1
        AND  tc.table_name      = $2
        AND  tc.constraint_type = 'FOREIGN KEY'
      ORDER  BY kcu.column_name
      `,
            [schema, table],
        );

        // ── Incoming references (who FK-points at this table?) ─────────────────
        const { rows: refRows } = await client.query<{
            from_schema: string;
            from_table: string;
            from_column: string;
        }>(
            `
      SELECT
        tc.table_schema  AS from_schema,
        tc.table_name    AS from_table,
        kcu.column_name  AS from_column
      FROM   information_schema.table_constraints       tc
      JOIN   information_schema.key_column_usage        kcu
               ON  kcu.constraint_name = tc.constraint_name
               AND kcu.table_schema    = tc.table_schema
      JOIN   information_schema.constraint_column_usage ccu
               ON  ccu.constraint_name = tc.constraint_name
      WHERE  ccu.table_schema   = $1
        AND  ccu.table_name     = $2
        AND  tc.constraint_type = 'FOREIGN KEY'
      ORDER  BY tc.table_schema, tc.table_name
      `,
            [schema, table],
        );

        // ── Row-count estimate from pg_stat (cheap; avoids COUNT(*)) ──────────
        const { rows: countRows } = await client.query<{
            estimate: string;
            is_view: boolean;
        }>(
            `
      SELECT
        reltuples::bigint::text                                   AS estimate,
        (relkind = 'v' OR relkind = 'm')                          AS is_view
      FROM   pg_class      c
      JOIN   pg_namespace  n ON n.oid = c.relnamespace
      WHERE  n.nspname = $1
        AND  c.relname = $2
      `,
            [schema, table],
        );

        const rowEstimate = Number(countRows[0]?.estimate ?? -1);
        const isView = Boolean(countRows[0]?.is_view);

        return {
            schema,
            table,
            isView,
            rowEstimate,
            columns: colRows.map((r) => ({
                name: r.name,
                type: r.type,
                nullable: r.nullable === "YES",
                default: r.default_val ?? undefined,
                isPrimaryKey: Boolean(r.is_pk),
            })),
            indexes: idxRows.map((r) => ({
                name: r.name,
                columns: r.columns,
                isUnique: Boolean(r.is_unique),
                isPrimary: Boolean(r.is_primary),
                method: r.method,
            })),
            foreignKeys: fkRows.map((r) => ({
                column: r.column,
                referencesSchema: r.ref_schema,
                referencesTable: r.ref_table,
                referencesColumn: r.ref_column,
                onDelete: r.on_delete,
            })),
            incomingRefs: refRows.map((r) => ({
                fromSchema: r.from_schema,
                fromTable: r.from_table,
                fromColumn: r.from_column,
            })),
        } satisfies TableDefinition;
    });

    setCached(cacheKey, definition);
    return definition;
}

/** Render a compact, DDL-inspired text representation of a table definition. */
function renderTableDDL(def: TableDefinition): string {
    const kind = def.isView ? "VIEW" : "TABLE";
    const rowLine =
        def.rowEstimate >= 0
            ? `  -- ~${def.rowEstimate.toLocaleString()} rows (pg_stat estimate)`
            : "";

    const colLines = def.columns.map((c) => {
        const tags: string[] = [];
        if (c.isPrimaryKey) tags.push("PK");
        if (!c.nullable) tags.push("NOT NULL");
        if (c.default !== undefined) tags.push(`DEFAULT ${c.default}`);
        const tagStr = tags.length > 0 ? `  -- ${tags.join(", ")}` : "";
        return `  ${c.name.padEnd(30)} ${c.type.toUpperCase()}${tagStr}`;
    });

    const sections: string[] = [
        `${kind} ${def.schema}.${def.table}`,
        rowLine,
        "(",
        colLines.join(",\n"),
        ");",
    ].filter(Boolean);

    if (def.foreignKeys.length > 0) {
        sections.push(
            "\nFOREIGN KEYS",
            def.foreignKeys
                .map(
                    (fk) =>
                        `  ${fk.column} → ${fk.referencesSchema}.${fk.referencesTable}.${fk.referencesColumn}` +
                        `  [ON DELETE ${fk.onDelete}]`,
                )
                .join("\n"),
        );
    }

    if (def.incomingRefs.length > 0) {
        sections.push(
            "\nREFERENCED BY",
            def.incomingRefs
                .map((r) => `  ${r.fromSchema}.${r.fromTable}.${r.fromColumn}`)
                .join("\n"),
        );
    }

    if (def.indexes.length > 0) {
        sections.push(
            "\nINDEXES",
            def.indexes
                .map((ix) => {
                    const flags = [ix.method.toUpperCase()];
                    if (ix.isPrimary) flags.push("PRIMARY");
                    else if (ix.isUnique) flags.push("UNIQUE");
                    return `  [${flags.join(" ")}] (${ix.columns.join(", ")})  -- ${ix.name}`;
                })
                .join("\n"),
        );
    }

    return sections.join("\n");
}

// ── Catalog: bulk schema snapshot ──────────────────────────────────────────────
//
// A single read covering ~80% of the schema reconnaissance an agent needs:
// every table with its columns (name + type + PK), every foreign key, and every
// enum, plus the database header. Designed as the "read-first" resource - it
// usually replaces fan-out across postgres://schemas + N × postgres://table/...
// Four queries on a single pooled connection; results are grouped in memory and
// cached under MCP_SCHEMA_CACHE_TTL_MS.

async function fetchCatalog(): Promise<Catalog> {
    const cacheKey = "catalog";
    const cached = getCached<Catalog>(cacheKey);
    if (cached) return cached;

    logDebug("Building catalog from live schema");

    const catalog = await withDb(async (client) => {
        // ── Header ─────────────────────────────────────────────────────────────
        const { rows: hdrRows } = await client.query<{
            db: string;
            version: string;
        }>(
            `SELECT current_database()                                            AS db,
              split_part(version(), ' ', 1) || ' ' || split_part(version(), ' ', 2)
                                                                            AS version`,
        );

        // ── User schemas ──────────────────────────────────────────────────────
        const { rows: schemaRows } = await client.query<{ schema: string }>(`
      SELECT DISTINCT table_schema AS schema
      FROM   information_schema.tables
      WHERE  table_schema NOT IN ('pg_catalog','information_schema')
      ORDER  BY table_schema
    `);

        // ── Tables × columns × PK in one pass ─────────────────────────────────
        const { rows: tableColRows } = await client.query<{
            schema: string;
            name: string;
            kind: "TABLE" | "VIEW";
            rows: string;
            column_name: string;
            column_type: string;
            is_pk: boolean;
        }>(`
      WITH pk_cols AS (
        SELECT kcu.table_schema, kcu.table_name, kcu.column_name
        FROM   information_schema.key_column_usage  kcu
        JOIN   information_schema.table_constraints tc
                 ON  tc.constraint_name = kcu.constraint_name
                 AND tc.table_schema    = kcu.table_schema
        WHERE  tc.constraint_type = 'PRIMARY KEY'
      )
      SELECT
        n.nspname                                                       AS schema,
        c.relname                                                       AS name,
        CASE WHEN c.relkind IN ('v','m') THEN 'VIEW' ELSE 'TABLE' END   AS kind,
        c.reltuples::bigint::text                                       AS rows,
        col.column_name                                                 AS column_name,
        CASE
          WHEN col.data_type = 'USER-DEFINED' THEN col.udt_name
          WHEN col.character_maximum_length IS NOT NULL
            THEN col.data_type || '(' || col.character_maximum_length || ')'
          ELSE col.data_type
        END                                                             AS column_type,
        (pk.column_name IS NOT NULL)                                    AS is_pk
      FROM   pg_class       c
      JOIN   pg_namespace   n  ON n.oid = c.relnamespace
      JOIN   information_schema.columns col
               ON  col.table_schema = n.nspname
               AND col.table_name   = c.relname
      LEFT   JOIN pk_cols pk
               ON  pk.table_schema = n.nspname
               AND pk.table_name   = c.relname
               AND pk.column_name  = col.column_name
      WHERE  n.nspname NOT IN ('pg_catalog','information_schema')
        AND  c.relkind IN ('r','v','m','p')
      ORDER  BY n.nspname, c.relname, col.ordinal_position
    `);

        // ── All foreign keys, single round-trip ───────────────────────────────
        const { rows: fkRows } = await client.query<{
            schema: string;
            name: string;
            col: string;
            ref_schema: string;
            ref_table: string;
            ref_column: string;
        }>(`
      SELECT
        tc.table_schema  AS schema,
        tc.table_name    AS name,
        kcu.column_name  AS col,
        ccu.table_schema AS ref_schema,
        ccu.table_name   AS ref_table,
        ccu.column_name  AS ref_column
      FROM   information_schema.table_constraints       tc
      JOIN   information_schema.key_column_usage        kcu
               ON  kcu.constraint_name = tc.constraint_name
               AND kcu.table_schema    = tc.table_schema
      JOIN   information_schema.constraint_column_usage ccu
               ON  ccu.constraint_name = tc.constraint_name
      WHERE  tc.constraint_type = 'FOREIGN KEY'
        AND  tc.table_schema NOT IN ('pg_catalog','information_schema')
      ORDER  BY tc.table_schema, tc.table_name, kcu.ordinal_position
    `);

        // ── Enum types ────────────────────────────────────────────────────────
        const { rows: enumRows } = await client.query<{
            schema: string;
            name: string;
            values: string[];
        }>(`
      SELECT
        n.nspname                                          AS schema,
        t.typname                                          AS name,
        array_agg(e.enumlabel ORDER BY e.enumsortorder)    AS values
      FROM   pg_type      t
      JOIN   pg_enum      e ON e.enumtypid   = t.oid
      JOIN   pg_namespace n ON n.oid          = t.typnamespace
      GROUP  BY n.nspname, t.typname
      ORDER  BY n.nspname, t.typname
    `);

        // ── Group columns and FKs onto their parent table ─────────────────────
        const tablesByKey = new Map<string, CatalogTable>();

        for (const r of tableColRows) {
            const key = `${r.schema}.${r.name}`;
            let tbl = tablesByKey.get(key);
            if (!tbl) {
                tbl = {
                    schema: r.schema,
                    name: r.name,
                    kind: r.kind,
                    rows: Number(r.rows),
                    columns: [],
                    fks: [],
                };
                tablesByKey.set(key, tbl);
            }
            const col: CatalogColumn = {
                name: r.column_name,
                type: r.column_type,
            };
            if (r.is_pk) col.pk = true;
            tbl.columns.push(col);
        }

        for (const r of fkRows) {
            const tbl = tablesByKey.get(`${r.schema}.${r.name}`);
            if (tbl) {
                tbl.fks.push({
                    col: r.col,
                    ref: `${r.ref_schema}.${r.ref_table}.${r.ref_column}`,
                });
            }
        }

        return {
            database: hdrRows[0]?.db ?? "",
            version: hdrRows[0]?.version ?? "",
            schemas: schemaRows.map((r) => r.schema),
            tables: Array.from(tablesByKey.values()),
            enums: enumRows.map((r) => ({
                schema: r.schema,
                name: r.name,
                values: r.values,
            })),
        } satisfies Catalog;
    });

    setCached(cacheKey, catalog);
    return catalog;
}

// ── Schema-aware error enrichment ─────────────────────────────────────────────
//
// PostgreSQL error codes relevant to schema mistakes:
//   42703  undefined_column  - "column X does not exist"
//   42P01  undefined_table   - "relation X does not exist"
//
// When the model sends a query with wrong names, we extract the missing
// identifier from the error message, search for similar objects in the schema,
// and return them alongside the error so the model can self-correct in one
// round-trip instead of two.

const SCHEMA_ERROR_CODES = new Set(["42703", "42P01"]);

async function autoSchemaHint(errorMessage: string): Promise<string> {
    // Extract the missing identifier from PostgreSQL's error format:
    //   column "createdAt" does not exist
    //   relation "User" does not exist
    const match = /(?:column|relation|table)\s+"([^"]+)"/i.exec(errorMessage);
    if (!match) return "";

    const missing = match[1];
    const pattern = `%${missing}%`;

    try {
        const rows = await withDb(async (client) => {
            const { rows } = await client.query<{
                schema: string;
                object_name: string;
                object_type: string;
                detail: string | null;
            }>(
                `
        SELECT schema, object_name, object_type, detail
        FROM (
          SELECT
            table_schema  AS schema,
            table_name    AS object_name,
            table_type    AS object_type,
            NULL          AS detail,
            1             AS rank
          FROM  information_schema.tables
          WHERE table_schema NOT IN ('pg_catalog','information_schema')
            AND table_name   ILIKE $1

          UNION ALL

          SELECT
            c.table_schema                             AS schema,
            c.table_name                               AS object_name,
            'COLUMN'                                   AS object_type,
            c.column_name || '  ' || c.data_type       AS detail,
            2                                          AS rank
          FROM  information_schema.columns c
          WHERE c.table_schema NOT IN ('pg_catalog','information_schema')
            AND c.column_name   ILIKE $1
        ) AS matches
        ORDER  BY rank, schema, object_name
        LIMIT  12
        `,
                [pattern],
            );
            return rows;
        });

        if (rows.length === 0) {
            return `\n\nNo schema objects found matching "${missing}". Use search_schema to explore the schema.`;
        }

        const lines = rows.map((r) =>
            r.detail
                ? `  [${r.object_type}] ${r.schema}.${r.object_name} - ${r.detail}`
                : `  [${r.object_type}] ${r.schema}.${r.object_name}`,
        );

        return (
            `\n\nSimilar schema objects matching "${missing}":\n${lines.join("\n")}` +
            `\n\nRead postgres://table/{schema}/{table} to get the full column list before retrying.`
        );
    } catch {
        return "";
    }
}

// ── MCP Server ─────────────────────────────────────────────────────────────────

const server = new McpServer({ name: "postgres", version: "1.0.0" });

// ══════════════════════════════════════════════════════════════════════════════
// RESOURCES - application-controlled schema knowledge the model reads as context
// ══════════════════════════════════════════════════════════════════════════════

// ── 1. Database overview ───────────────────────────────────────────────────────
server.registerResource(
    "overview",
    "postgres://overview",
    {
        mimeType: "application/json",
        description:
            "Database name, Postgres version, total size, and table/view/schema counts. Read this first.",
    },
    async () => {
        const cacheKey = "overview";
        const hit = getCached<unknown>(cacheKey);

        const data =
            hit ??
            (await withDb(async (client) => {
                const { rows } = await client.query(`
          SELECT
            current_database()                                                AS name,
            pg_size_pretty(pg_database_size(current_database()))              AS size,
            split_part(version(), ' ', 1) || ' ' || split_part(version(), ' ', 2) AS version,
            (SELECT count(*)::int
               FROM information_schema.tables
              WHERE table_schema NOT IN ('pg_catalog','information_schema')
                AND table_type = 'BASE TABLE')                                AS tables,
            (SELECT count(*)::int
               FROM information_schema.tables
              WHERE table_schema NOT IN ('pg_catalog','information_schema')
                AND table_type = 'VIEW')                                      AS views,
            (SELECT count(DISTINCT table_schema)::int
               FROM information_schema.tables
              WHERE table_schema NOT IN ('pg_catalog','information_schema'))   AS schemas
        `);
                return rows[0];
            }));

        if (!hit) setCached(cacheKey, data);

        return {
            contents: [
                {
                    uri: "postgres://overview",
                    mimeType: "application/json",
                    text: JSON.stringify(data, null, 2),
                },
            ],
        };
    },
);

// ── 2. Schema catalogue ────────────────────────────────────────────────────────
server.registerResource(
    "schemas",
    "postgres://schemas",
    {
        mimeType: "application/json",
        description: "All user schemas with their table and view counts.",
    },
    async () => {
        const cacheKey = "schemas";
        const hit = getCached<unknown[]>(cacheKey);

        const data =
            hit ??
            (await withDb(async (client) => {
                const { rows } = await client.query(`
          SELECT
            t.table_schema                                                      AS schema,
            count(*) FILTER (WHERE t.table_type = 'BASE TABLE')::int           AS tables,
            count(*) FILTER (WHERE t.table_type = 'VIEW')::int                 AS views
          FROM   information_schema.tables t
          WHERE  t.table_schema NOT IN ('pg_catalog','information_schema')
          GROUP  BY t.table_schema
          ORDER  BY t.table_schema
        `);
                return rows;
            }));

        if (!hit) setCached(cacheKey, data);

        return {
            contents: [
                {
                    uri: "postgres://schemas",
                    mimeType: "application/json",
                    text: JSON.stringify(data, null, 2),
                },
            ],
        };
    },
);

// ── 3. Table / view definition (URI template) ──────────────────────────────────

const tableTemplate = new ResourceTemplate(
    "postgres://table/{schema}/{table}",
    {
        list: async () => {
            const cacheKey = "table-list";
            const hit =
                getCached<
                    Array<{ uri: string; name: string; mimeType: string }>
                >(cacheKey);

            const resources =
                hit ??
                (await withDb(async (client) => {
                    const { rows } = await client.query<{
                        schema: string;
                        table: string;
                    }>(`
          SELECT table_schema AS schema, table_name AS table
          FROM   information_schema.tables
          WHERE  table_schema NOT IN ('pg_catalog','information_schema')
            AND  table_type   IN ('BASE TABLE','VIEW')
          ORDER  BY table_schema, table_name
        `);
                    return rows.map((r) => ({
                        uri: `postgres://table/${r.schema}/${r.table}`,
                        name: `${r.schema}.${r.table}`,
                        mimeType: "text/plain",
                    }));
                }));

            // Shorter TTL than other caches: this list is what the host enumerates first,
            // so a stale list hides newly-migrated tables for an entire cache window.
            if (!hit) setCached(cacheKey, resources, LIST_CACHE_TTL_MS);
            return { resources };
        },
    },
);

server.registerResource(
    "table",
    tableTemplate,
    {
        mimeType: "text/plain",
        description:
            "Full DDL for a table or view: columns, types, nullability, defaults, primary key, " +
            "foreign keys, incoming references, indexes, and estimated row count.",
    },
    async (uri: URL, variables: Record<string, string | string[]>) => {
        const schema = String(variables["schema"] ?? "");
        const table = String(variables["table"] ?? "");

        if (!schema || !table) {
            return {
                contents: [
                    {
                        uri: uri.href,
                        mimeType: "text/plain",
                        text: "Missing schema or table in URI.",
                    },
                ],
            };
        }

        try {
            const def = await fetchTableDefinition(schema, table);
            return {
                contents: [
                    {
                        uri: uri.href,
                        mimeType: "text/plain",
                        text: renderTableDDL(def),
                    },
                ],
            };
        } catch (err) {
            return {
                contents: [
                    {
                        uri: uri.href,
                        mimeType: "text/plain",
                        text: `Could not fetch definition for ${schema}.${table}: ${String(err)}`,
                    },
                ],
            };
        }
    },
);

// ── 4. Enum types ──────────────────────────────────────────────────────────────
server.registerResource(
    "enums",
    "postgres://enums",
    {
        mimeType: "application/json",
        description:
            "All user-defined PostgreSQL enum types and their allowed values.",
    },
    async () => {
        const cacheKey = "enums";
        const hit = getCached<unknown[]>(cacheKey);

        const data =
            hit ??
            (await withDb(async (client) => {
                const { rows } = await client.query(`
          SELECT
            n.nspname                                              AS schema,
            t.typname                                             AS name,
            array_agg(e.enumlabel ORDER BY e.enumsortorder)      AS values
          FROM   pg_type      t
          JOIN   pg_enum      e ON e.enumtypid   = t.oid
          JOIN   pg_namespace n ON n.oid          = t.typnamespace
          GROUP  BY n.nspname, t.typname
          ORDER  BY n.nspname, t.typname
        `);
                return rows;
            }));

        if (!hit) setCached(cacheKey, data);

        return {
            contents: [
                {
                    uri: "postgres://enums",
                    mimeType: "application/json",
                    text: JSON.stringify(data, null, 2),
                },
            ],
        };
    },
);

// ── 5. Catalog - read-first bulk overview ──────────────────────────────────────
server.registerResource(
    "catalog",
    "postgres://catalog",
    {
        mimeType: "application/json",
        description:
            "Compact one-shot snapshot of the schema: every table with its columns " +
            "(name, type, primary-key flag), every foreign key, every enum, plus the " +
            "database header. Read this first - it usually replaces fan-out across " +
            "postgres://schemas and per-table reads.",
    },
    async () => {
        const data = await fetchCatalog();
        return {
            contents: [
                {
                    uri: "postgres://catalog",
                    mimeType: "application/json",
                    // Compact (no indentation) - payload is consumed by the model, not a human.
                    text: JSON.stringify(data),
                },
            ],
        };
    },
);

// ══════════════════════════════════════════════════════════════════════════════
// TOOLS - model-controlled operations
// ══════════════════════════════════════════════════════════════════════════════

// ── Tool 1: query ──────────────────────────────────────────────────────────────
server.registerTool(
    "query",
    {
        description:
            "Execute a read-only SQL query and return results as JSON. " +
            "Only SELECT, WITH, EXPLAIN, SHOW, TABLE, and VALUES are allowed. " +
            "A LIMIT is automatically injected when absent.",
        inputSchema: {
            sql: z
                .string()
                .min(1)
                .describe("Read-only SQL statement to execute."),
            limit: z
                .number()
                .int()
                .min(1)
                .max(5_000)
                .optional()
                .default(ROW_LIMIT)
                .describe(`Maximum rows to return. Defaults to ${ROW_LIMIT}.`),
        },
        annotations: {
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
        },
    },
    async ({ sql, limit }) => {
        const validationError = validateReadOnly(sql);
        if (validationError) {
            return {
                content: [
                    {
                        type: "text",
                        text: `Validation error: ${validationError}`,
                    },
                ],
                isError: true,
            };
        }

        const bounded = injectRowLimit(sql, limit ?? ROW_LIMIT);
        logDebug(`query: ${bounded.slice(0, 120)}`);

        try {
            const { rows, rowCount } = await withDb(async (client) =>
                client.query(bounded),
            );
            return {
                content: [
                    {
                        type: "text",
                        text: JSON.stringify(
                            { rowCount: rowCount ?? rows.length, rows },
                            null,
                            2,
                        ),
                    },
                ],
            };
        } catch (rawErr: unknown) {
            const pgErr = rawErr as {
                code?: string;
                message?: string;
                hint?: string;
            };
            const message = pgErr.message ?? String(rawErr);
            const hint = pgErr.hint ? `\nPostgres hint: ${pgErr.hint}` : "";

            const schemaHint = SCHEMA_ERROR_CODES.has(pgErr.code ?? "")
                ? await autoSchemaHint(message)
                : "";

            return {
                content: [
                    {
                        type: "text",
                        text: `Database error: ${message}${hint}${schemaHint}`,
                    },
                ],
                isError: true,
            };
        }
    },
);

// ── Tool 2: explain ────────────────────────────────────────────────────────────
server.registerTool(
    "explain",
    {
        description:
            "Run EXPLAIN on a SQL query to inspect its query plan. " +
            "With analyze=true (default) the query is actually executed so you get real timing and row estimates. " +
            "Safe in read-only mode because only SELECT queries are accepted.",
        inputSchema: {
            sql: z.string().min(1).describe("SQL statement to explain."),
            analyze: z
                .boolean()
                .optional()
                .default(true)
                .describe(
                    "Include ANALYZE + BUFFERS for real execution statistics. Default: true.",
                ),
        },
        annotations: {
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: false,
        },
    },
    async ({ sql, analyze }) => {
        const validationError = validateReadOnly(sql);
        if (validationError) {
            return {
                content: [
                    {
                        type: "text",
                        text: `Validation error: ${validationError}`,
                    },
                ],
                isError: true,
            };
        }

        const explainSql = analyze
            ? `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) ${sql}`
            : `EXPLAIN (FORMAT TEXT) ${sql}`;

        logDebug(`explain (analyze=${String(analyze)}): ${sql.slice(0, 80)}`);

        try {
            const plan = await withDb(async (client) => {
                const { rows } = await client.query(explainSql);
                // EXPLAIN returns one row per plan line; join into a single string
                return rows
                    .map((r: Record<string, unknown>) =>
                        String(Object.values(r)[0] ?? ""),
                    )
                    .join("\n");
            });
            return { content: [{ type: "text", text: plan }] };
        } catch (err) {
            return {
                content: [
                    { type: "text", text: `Explain error: ${String(err)}` },
                ],
                isError: true,
            };
        }
    },
);

// ── Tool 3: search_schema ──────────────────────────────────────────────────────
server.registerTool(
    "search_schema",
    {
        description:
            "Case-insensitive substring search across table names, column names, and enum type names. " +
            "Returns ranked matches with context. " +
            'Use this when you have a specific term to look for: "tables matching %invoice%", ' +
            '"columns named like %_at", "enum type whose name contains role". ' +
            "For a full overview of the schema, read postgres://catalog instead - one read covers " +
            "every table, column, foreign key, and enum.",
        inputSchema: {
            pattern: z
                .string()
                .min(1)
                .describe(
                    "Search term - case-insensitive substring match. " +
                        "Use % as a wildcard (e.g. '%user%'). Wildcards are added automatically if absent.",
                ),
            limit: z
                .number()
                .int()
                .min(1)
                .max(200)
                .optional()
                .default(50)
                .describe("Maximum results to return. Default: 50."),
        },
        annotations: {
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
        },
    },
    async ({ pattern, limit }) => {
        // Surround with wildcards unless the caller already included %
        const p = pattern.includes("%") ? pattern : `%${pattern}%`;
        logDebug(`search_schema: pattern="${p}"`);

        try {
            const rows = await withDb(async (client) => {
                const { rows } = await client.query<{
                    schema: string;
                    object_name: string;
                    object_type: string;
                    detail: string | null;
                }>(
                    `
          SELECT schema, object_name, object_type, detail
          FROM (
            -- Tables and views whose name matches
            SELECT
              table_schema  AS schema,
              table_name    AS object_name,
              table_type    AS object_type,
              NULL          AS detail,
              1             AS rank
            FROM  information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog','information_schema')
              AND table_name   ILIKE $1

            UNION ALL

            -- Columns whose name matches (grouped by parent table)
            SELECT
              c.table_schema          AS schema,
              c.table_name            AS object_name,
              'COLUMN'                AS object_type,
              c.column_name || '  ' || c.data_type AS detail,
              2                       AS rank
            FROM  information_schema.columns c
            WHERE c.table_schema NOT IN ('pg_catalog','information_schema')
              AND c.column_name   ILIKE $1

            UNION ALL

            -- Enum types whose name matches
            SELECT
              n.nspname       AS schema,
              t.typname       AS object_name,
              'ENUM'          AS object_type,
              array_to_string(
                array_agg(e.enumlabel ORDER BY e.enumsortorder), ' | '
              )               AS detail,
              3               AS rank
            FROM   pg_type      t
            JOIN   pg_enum      e ON e.enumtypid   = t.oid
            JOIN   pg_namespace n ON n.oid          = t.typnamespace
            WHERE  t.typname ILIKE $1
            GROUP  BY n.nspname, t.typname
          ) AS matches
          ORDER  BY rank, schema, object_name
          LIMIT  $2
          `,
                    [p, limit ?? 50],
                );
                return rows;
            });

            if (rows.length === 0) {
                return {
                    content: [
                        {
                            type: "text",
                            text: `No schema objects found matching "${pattern}".`,
                        },
                    ],
                };
            }

            const lines = rows.map((r) =>
                r.detail
                    ? `[${r.object_type}] ${r.schema}.${r.object_name}  -  ${r.detail}`
                    : `[${r.object_type}] ${r.schema}.${r.object_name}`,
            );

            return {
                content: [
                    {
                        type: "text",
                        text: `Found ${rows.length} result(s) for "${pattern}":\n\n${lines.join("\n")}`,
                    },
                ],
            };
        } catch (err) {
            return {
                content: [
                    { type: "text", text: `Search error: ${String(err)}` },
                ],
                isError: true,
            };
        }
    },
);

// ══════════════════════════════════════════════════════════════════════════════
// PROMPTS - user-triggered reusable templates
// ══════════════════════════════════════════════════════════════════════════════

server.registerPrompt(
    "explore-database",
    {
        description:
            "A step-by-step protocol for systematically mapping an unfamiliar database before writing queries.",
    },
    () => ({
        messages: [
            {
                role: "user" as const,
                content: {
                    type: "text" as const,
                    text: `You are about to help me explore an unknown PostgreSQL database.

Follow this systematic protocol - do not skip steps:

1. READ postgres://overview
   Understand the database name, Postgres version, total size, and rough scale
   (number of tables, views, schemas).

2. READ postgres://schemas
   Identify the user schemas. Ignore pg_catalog and information_schema.

3. Discover key domain tables
   For each schema that looks interesting, call search_schema with broad patterns
   that reflect likely domain nouns (e.g. "%user%", "%order%", "%account%",
   "%event%", "%payment%"). Start wide, narrow from there.

4. Read table definitions for the 4-6 most central tables
   READ postgres://table/{schema}/{table} for each candidate.
   Note columns, types, FK relationships, and row-count estimates.

5. READ postgres://enums
   Enum types encode domain vocabulary - they reveal the allowed states and
   categories of the data model.

6. Produce a written summary:
   - Domain model in plain language
   - Entity-relationship sketch (entity → FK → entity)
   - Estimated data volume per key table
   - Any surprising or noteworthy schema patterns

Only write or execute SQL queries (via the query tool) after this context is built.`,
                },
            },
        ],
    }),
);

server.registerPrompt(
    "write-query",
    {
        description:
            "Guided workflow for constructing a correct, well-scoped SQL query from a plain-language goal.",
        argsSchema: {
            goal: z.string().describe("What data do you want to retrieve?"),
        },
    },
    ({ goal }) => ({
        messages: [
            {
                role: "user" as const,
                content: {
                    type: "text" as const,
                    text: `I need a SQL query that achieves the following goal:

${goal}

Before writing any SQL, follow these steps:

1. Use search_schema to discover tables and columns relevant to this goal.
   Try multiple patterns if the first attempt returns nothing useful.

2. For each candidate table, READ postgres://table/{schema}/{table} to
   understand: column types, nullability, default values, primary keys,
   FK join paths, and row-count estimates.

3. Draft the query. Reason through:
   - Which tables to join and which FK columns to join on
   - Filters that narrow to only the data needed
   - Whether GROUP BY, aggregates, or window functions are appropriate
   - Whether the result set needs LIMIT or pagination

4. Run the draft via query(sql, limit=10) to verify the shape of results.
   Fix any errors before expanding the limit.

5. If the query is slow, run explain(sql) to inspect the plan.
   Identify missing indexes or expensive full-table scans.

Return:
- The final SQL query, formatted for readability
- A one-paragraph explanation of each join, filter, and aggregate
- Any caveats about data quality or edge cases in the schema`,
                },
            },
        ],
    }),
);

// ── Graceful shutdown ──────────────────────────────────────────────────────────

async function shutdown(reason: string): Promise<never> {
    logInfo(`Shutting down (${reason}).`);
    try {
        await pool.end();
    } catch (err) {
        logError("Error draining pool", err);
    }
    process.exit(0);
}

process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("uncaughtException", (err) => {
    logError("Uncaught exception", err);
    void shutdown("uncaughtException");
});
process.on("unhandledRejection", (reason) => {
    logError("Unhandled rejection", reason);
});

// ── Entry point ────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
    logInfo(`Connecting to ${safeUrl(DATABASE_URL)} …`);

    // Fail fast: verify connectivity before advertising tools to the client
    await withDb(async (client) => {
        const { rows } = await client.query<{ db: string; ver: string }>(
            "SELECT current_database() AS db, split_part(version(),' ',2) AS ver",
        );
        logInfo(
            `Connected: database="${rows[0]?.db}", PostgreSQL ${rows[0]?.ver}`,
        );
    });

    const transport = new StdioServerTransport();
    await server.connect(transport);
    logInfo("MCP server ready - listening on stdio.");
}

main().catch((err) => {
    logError("Fatal startup error", err);
    process.exit(1);
});
