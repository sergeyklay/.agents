---
description: 'JSDoc comment style, exported symbol documentation, inline comment rules, and deprecation patterns for TypeScript and React code.'
applyTo: '**/*.ts,**/*.tsx'
---

# TypeScript & React Documentation and Comments

TypeScript's type system documents *what* a symbol is. JSDoc documents *why* it exists, *what contract* it upholds, and *when* its behavior is non-obvious. Never duplicate information that the type signature already conveys.

---

## File-Level Comments

Every file that defines a public domain concept, service, or utility module must have a leading file-level comment. Place it before the first `import`.

- State what the module provides and its role within the architecture.
- Name the primary export the caller should start with.
- Do not restate the filename, list every export, or describe implementation internals.

```typescript
// ✅ Declarative, focused on role and entry point.
/**
 * Report generation pipeline for project dashboards.
 *
 * Entry point: {@link ReportBuilder}. Use {@link renderReportTemplate}
 * to convert a built report into an HTML string.
 */
import { ReportBuilder } from './report-builder';

// ❌ Restates the filename; no architectural context.
/**
 * report.ts — contains report stuff
 */
```

Omit the file-level comment entirely when the filename and its single export are self-explanatory (e.g., a one-function utility file).

---

## Exported Symbol Comments

### Structure

Every exported function, class, method, constant, and type alias must have a JSDoc comment. The comment follows a strict two-part structure.

**First line — mandatory summary.**
Begin with the symbol name as the grammatical subject. End at the first period. This line appears in IDE hover tooltips and TypeDoc index pages and must be self-contained.

```typescript
/**
 * Formats a monetary amount according to the active locale and currency.
 */
export function formatCurrency(amount: number, currency: string): string {
```

**Continuation block — conditional.**
Add a second paragraph only when the first sentence does not fully convey the contract: error behaviour, `null`/`undefined`-input semantics, side effects, or non-obvious preconditions. Limit to 3–4 sentences. A third paragraph is justified only for a separate semantic topic (e.g., a usage example after describing error behaviour).

```typescript
/**
 * Fetches the paginated list of documents owned by the given user.
 *
 * Returns an empty array when no documents exist — never `null`. Throws
 * {@link UnauthorizedError} if the session token is missing or expired.
 * Results are sorted by `updatedAt` descending.
 */
export async function listDocuments(userId: string): Promise<Document[]> {
```

### Tone and Phrasing

Use declarative, present-tense statements. Name what the symbol *does or reports*, not how to call it.

```typescript
// ✅ Declarative.
// Validates the form values against the active Zod schema.
// Reports whether the subscription plan includes the given feature flag.
// Resolves to the first matching record, or undefined if none exists.

// ❌ Imperative — tells the caller what to do, not what the symbol is.
// Call validate() to check the form values.
// Use this to check if the plan includes the feature.
// Returns first matching record.
```

---

## Parameters and Return Values

**Do not repeat type information in `@param` or `@returns` tags.** TypeScript already documents the type. JSDoc documents the *meaning*, *valid range*, or *contract*.

```typescript
// ✅ Explains meaning, not type.
/**
 * Schedules a report for background generation.
 *
 * @param reportId - Stable identifier of the report template to run.
 * @param delayMs - Minimum delay before execution; clamped to [0, 30_000].
 * @returns A job handle that can be used to cancel or monitor progress.
 */
export function scheduleReport(reportId: string, delayMs: number): JobHandle {

// ❌ Repeats type; adds no value.
/**
 * Schedules a report.
 *
 * @param reportId {string} The report ID string.
 * @param delayMs {number} The delay in milliseconds as a number.
 * @returns {JobHandle} Returns a JobHandle object.
 */
```

**When to include `@param`:**

| Situation | Include `@param`? |
|---|---|
| Parameter name is self-explanatory and type is scalar | No |
| Parameter has a non-obvious valid range or format | Yes |
| Parameter interacts with another parameter in a non-obvious way | Yes |
| Parameter has a special sentinel value (e.g., `0` means unlimited) | Yes |
| Callback parameter — document what it is called with | Yes |

**When to include `@returns`:**

Omit `@returns` when the return value is obvious from the summary and signature. Include it when the return value has a non-obvious invariant, sentinel, or ordering guarantee.

```typescript
// ✅ Return invariant is non-obvious.
/**
 * Resolves all pending uploads for the session.
 *
 * @returns Settled results in the same order as the original upload queue,
 *   including failures. Never rejects.
 */
async function drainUploadQueue(): Promise<UploadResult[]>

// ❌ Restates what the signature already says.
/**
 * Gets the user.
 *
 * @returns A Promise<User>.
 */
async function getUser(id: string): Promise<User>
```

---

## Generic Type Parameters

Document `@template` when the type parameter's semantic role is not obvious from its name alone.

```typescript
/**
 * Wraps a server action with optimistic UI state management.
 *
 * @template TInput - The validated input type accepted by the action.
 * @template TResult - The success result type returned on completion.
 * @param action - The server action to wrap.
 * @returns An object with `execute`, `isPending`, and `optimisticState`.
 */
export function useOptimisticAction<TInput, TResult>(
  action: (input: TInput) => Promise<ActionResult<TResult>>,
): OptimisticActionHook<TInput, TResult> {
```

Omit `@template` when the meaning is obvious from usage (e.g., `T` in `identity<T>(value: T): T`).

---

## Error Contracts

Document every thrown error that the caller is expected to handle. Use `@throws` with the error class name.

```typescript
/**
 * Parses and validates the raw webhook payload from the provider.
 *
 * @throws {SignatureVerificationError} If the request signature does not match.
 * @throws {MalformedPayloadError} If the JSON structure is missing required fields.
 */
export function parseWebhookPayload(raw: string, signature: string): WebhookEvent {
```

Do not document errors that are programming mistakes (e.g., passing `null` where the type disallows it) — those are type system violations, not contractual errors.

---

## React Components

### Props Interface

Document the props interface, not the component function, unless the component itself has a non-obvious rendering contract.

```typescript
// ✅ Document the interface; the component summary is brief.
/**
 * Props for {@link DataTable}.
 */
interface DataTableProps<TRow> {
  /** Rows to render. An empty array renders the empty-state slot. */
  rows: TRow[];

  /** Unique key extractor. Must be stable across re-renders. */
  getRowKey: (row: TRow) => string;

  /**
   * Optional override for the empty state. Defaults to a generic
   * "No data" message when omitted.
   */
  emptyState?: ReactNode;
}

/**
 * Virtualized data table for large row sets.
 */
export function DataTable<TRow>({ rows, getRowKey, emptyState }: DataTableProps<TRow>) {
```

### Rules for Component Comments

- The summary line names what the component *renders*, not how to use it.
- Document `children` only when the component imposes structural constraints (e.g., "must contain exactly one `<Tab>` per entry").
- Document `className` and `style` only when the component constrains which styles are safe to override.
- Do not document props whose name and type are entirely self-explanatory (`disabled?: boolean`, `placeholder?: string`).

```typescript
// ✅ Props comment focuses on constraints, not obvious fields.
interface ModalProps {
  /** Controlled open state. */
  open: boolean;

  /**
   * Called when the modal requests to close (Escape key or backdrop click).
   * The consumer is responsible for updating `open`.
   */
  onClose: () => void;

  /**
   * Disables backdrop click and Escape key dismissal.
   * Use for destructive confirmation flows where accidental dismissal loses context.
   */
  dismissible?: boolean;
}
```

### Server vs. Client Component Boundary

When a component intentionally straddles the RSC boundary, document the boundary contract:

```typescript
/**
 * Server-rendered skeleton of the activity feed.
 *
 * Fetches initial entries on the server; delegates live updates to
 * {@link ActivityFeedClient} via a streamed `initialEntries` prop.
 */
export async function ActivityFeed({ userId }: ActivityFeedProps) {
```

---

## React Hooks

Hooks require the most thorough documentation because their return shape, side-effect lifecycle, and dependency constraints are rarely obvious from the signature.

**Required sections for non-trivial hooks:**
1. Summary — what the hook manages.
2. Side-effect contract — what effects it registers and when they clean up.
3. `@param` for non-obvious parameters.
4. `@returns` describing the shape and key invariants of the returned object.
5. `@example` when the hook has a non-trivial call site.

```typescript
/**
 * Manages polling for a background job until it reaches a terminal state.
 *
 * Starts polling immediately on mount if `jobId` is provided. Stops and
 * cleans up the interval when the job reaches `'completed'` or `'failed'`,
 * or when the component unmounts. Re-starts if `jobId` changes.
 *
 * @param jobId - The job to poll, or `null` to skip polling.
 * @param intervalMs - Polling interval; defaults to 2000. Clamped to [500, 30_000].
 * @returns An object with `status`, `result`, `error`, and `cancel`.
 *
 * @example
 * const { status, result } = useJobPoller(submittedJobId);
 * if (status === 'completed') showSuccessToast(result.summary);
 */
export function useJobPoller(
  jobId: string | null,
  intervalMs = 2_000,
): JobPollerState {
```

---

## Interfaces and Type Aliases

### Interfaces

Document every property whose meaning, valid range, or nullability is not fully conveyed by its name and type.

```typescript
/**
 * Configuration for the PDF generation pipeline.
 */
export interface PdfOptions {
  /**
   * Page format. Defaults to `'A4'`.
   * Accepts any value supported by Puppeteer's `Page.pdf()` format option.
   */
  format?: 'A4' | 'Letter' | 'Legal';

  /**
   * Margin in millimeters applied to all four sides.
   * Set to `0` for bleed-safe exports; never use negative values.
   */
  marginMm?: number;

  /** Include the watermark overlay registered under this key, if any. */
  watermarkKey?: string;
}
```

Do not add a JSDoc comment to every property automatically. Only document properties whose name and type leave a genuine question unanswered.

### Type Aliases

Document a type alias when it encodes a domain constraint that the structural type does not express:

```typescript
/**
 * An ISO-8601 date string in UTC, e.g. `"2025-03-14T00:00:00Z"`.
 * Do not pass local-time strings — the API rejects them.
 */
export type UtcDateString = string;
```

Omit comments on trivial aliases (`type UserId = string` needs no comment if used consistently).

---

## Cross-References

Use `{@link Symbol}` to link to related types, functions, and components. Prefer links over spelling out module paths in prose.

```typescript
/**
 * Low-level fetch wrapper used by {@link ApiClient}.
 * Prefer {@link ApiClient} for authenticated requests.
 */
export function rawFetch(url: string, init?: RequestInit): Promise<Response> {
```

---

## Deprecation

Mark deprecated symbols with `@deprecated`. Include the version or date of deprecation and the replacement.

```typescript
/**
 * @deprecated Since 2.4.0. Use {@link createReportV2} instead, which supports
 *   async templates and locale-aware formatting.
 */
export function createReport(template: string): Report {
```

Do not silently delete deprecated exports — consumers depend on them. Add `@deprecated` first; remove in the next major version.

---

## Code Examples

Include `@example` only when the composition pattern or call site is genuinely non-obvious. Keep examples minimal — they are not tutorials.

```typescript
/**
 * Registers a global error boundary for unhandled promise rejections.
 *
 * Must be called once at application startup, before any async work begins.
 *
 * @example
 * // app/layout.tsx
 * registerGlobalErrorBoundary({
 *   onError: (err) => logger.error('Unhandled rejection', err),
 *   reportToSentry: process.env.NODE_ENV === 'production',
 * });
 */
export function registerGlobalErrorBoundary(options: ErrorBoundaryOptions): void {
```

---

## Inline Comments

Reserve inline comments for **why**, not **what**. The code already says what it does; the comment explains the constraint, invariant, or workaround the reader cannot derive from the code alone.

```typescript
// ✅ Explains a non-obvious constraint.
// Chromium's PDF renderer silently truncates content beyond 14_400 px height;
// split into multiple pages above this threshold.
const MAX_PAGE_HEIGHT_PX = 14_400;

// Optimistic update applied before the server round-trip to keep the UI
// responsive; rolled back in the onError callback.
setItems((prev) => [optimisticItem, ...prev]);

// ❌ Narrates the code — the reader can see this.
// Set the variable to true
let isLoading = true;

// Loop over items and push to result array
for (const item of items) {
  result.push(transform(item));
}
```

**Never** place inline comments that:
- Restate a variable name in prose (`// user id` above `const userId`).
- Label obvious control flow (`// return`, `// if error`).
- Reference internal ticket numbers, sprint sections, or wiki links — these rot.

Upstream workaround references (MDN issue numbers, browser bug IDs, `react/issues/NNNN`) are permitted **only** when they explain a hack that cannot be fully described in one sentence of prose.

---

## What to Avoid

| Pattern | Why to avoid |
|---|---|
| `@param {string} name` — type in `@param` | TypeScript already documents the type; repeating it creates drift |
| `@returns {Promise<User>}` — type in `@returns` | Same reason |
| Comments on every property of a simple DTO | Adds noise; reserve for non-obvious fields only |
| `// TODO: fix later` without owner or ticket | Unactionable; use a tracked issue |
| Comments referencing internal docs, ADRs, or sprint numbers | These rot; put the relevant context directly in the comment |
| Restating what the implementation does (`// calls fetchUser then maps result`) | Implementation is visible; only document the *contract* |
| Tutorial-style prose in JSDoc (`"This is a helper that helps you..."`) | Unprofessional; use declarative statements |
| Documenting every unexported symbol by default | Only document unexported symbols when the logic is genuinely non-obvious |

---

## ESLint Suppression

- Always name the rule: `// eslint-disable-next-line @typescript-eslint/no-explicit-any`.
- Always include a justification on the same line, separated by ` -- `:

```typescript
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- third-party event bus types are untyped at the call site
const handler = (payload: any) => processEvent(payload);
```

- Never use a bare `// eslint-disable` without a specific rule.
- Never suppress `@typescript-eslint/no-unsafe-*` rules across an entire file — fix the typing instead.
- Prefer fixing the code. Suppression is a last resort when the linter is provably wrong or the fix would harm readability more than the suppression harms safety.

---

## Checklist

Before finalizing a change:

- [ ] Every new exported symbol has a JSDoc summary line.
- [ ] `@param` tags present only where the meaning is not obvious from the name.
- [ ] No type annotations duplicated inside `@param` or `@returns` tags.
- [ ] `@throws` documented for every error the caller is expected to handle.
- [ ] `@deprecated` includes version/date and a replacement reference.
- [ ] `@example` present for hooks and functions with non-obvious call sites.
- [ ] Inline comments explain *why*, not *what*.
- [ ] No comments referencing ticket numbers, ADR sections, or internal doc links.
- [ ] ESLint suppressions name the rule and include a justification.
