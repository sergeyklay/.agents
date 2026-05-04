---
description: 'Use when editing TypeScript or React code. Covers core TypeScript rules, naming, type placement, constants ownership, ORM imports, and React component fundamentals.'
applyTo: '**/*.ts,**/*.tsx'
---

# TypeScript & React Codestyle

Core TS/React rules that apply broadly.

## TypeScript Core

- `strict: true` is non-negotiable.
- Prefer `unknown` over `any`. Use `any` only at third-party boundaries with an ESLint suppression comment.
- Use `undefined` for absent values. Use `null` only for ORM columns or external API contracts that require it.
- Use `interface` for component props, domain model shapes, and service contracts.
- Use `type` for unions, intersections, mapped types, conditional types, and `z.infer`.
- Use `import type` for every type-only import.
- Avoid `!` non-null assertions. Narrow with a guard or throw.
- Use `const` unless reassignment is required. Never use `var`.

## Naming

| Construct | Convention | Example |
|---|---|---|
| Variables and functions | `camelCase` | `fetchOrders` |
| React components | `PascalCase` | `OrderCard` |
| Types and interfaces | `PascalCase` | `OrderCardProps` |
| Hooks | `use` + `camelCase` | `useAsyncAction` |
| Server Actions | verb + noun | `syncContacts` |
| Zod schemas | noun + `Schema` | `confirmMergeSchema` |
| Files | `kebab-case` | `merge-dialog.tsx` |

- Booleans use `is`, `has`, `can`, or `should` prefixes.
- Event handlers use `handle*` for local definitions and `on*` for props.

## Imports and Module Boundaries

- Group imports as: external, internal alias (`@/...`), relative, then type-only imports.
- Co-locate feature-specific code. Promote code to a shared `components/` only when two or more features share it.
- Avoid barrel `index.ts` re-exports inside feature directories. Import from the source file directly.

```typescript
import { Suspense } from 'react';

import { getDb } from '@/lib/db';
import { OrderCard } from '@/components/order/order-card';

import { OrderEmptyState } from './order-empty-state';

import type { Order } from '@/services/orders/order-queries';
```

## Type Placement Decision Tree

Choose the smallest scope that contains all consumers of a type.

1. **Single-use inline:** declare in the consuming file, do not export.
2. **ORM-generated:** import through the project's ORM alias (commonly `@db` or `@/lib/db`), not via relative paths into generated code.
3. **Server Action DTO:** export from the action module or a colocated `<feature>-contract.ts` when shared. Use a transport-role suffix such as `*Dto`.
4. **Zod-derived input:** derive with `z.infer<typeof schema>`. Keep the schema in the action file unless multiple modules share it; then colocate it in `<feature>-contract.ts`.
5. **Route-segment view-model:** keep in `app/<route>/*-view-model.ts`.
6. **Cross-feature shared type:** colocate at the smallest shared boundary (`lib/<domain>/<feature>-contract.ts` or feature-local `.types.ts`).

Additional rules:

- Do not add new global domain buckets under `src/types/`.
- Reserve `src/types/` for ambient declarations and cross-cutting transport contracts (e.g. `ActionResult`).
- Keep service-layer return types distinct from Server Action DTOs. Actions build DTOs explicitly; services return service-shaped data.

## Constants and Configuration

Apply the same ownership logic as for types. Every literal has one owner.

### Three owners

| Owner | Location | Holds |
|---|---|---|
| Env schema | `lib/env/{server,shared}.ts` | Secrets and values that change per environment without rebuild (`AUTH_SECRET`, `DATABASE_URL`, cron schedules, feature budgets, TTLs) |
| Feature constants | `<feature>/constants.ts` (or `*-contract.ts` alongside schemas) | Stable rules owned by one service, route, or feature |
| Cross-cutting | `lib/constants/<concept>.ts` | Stable rules genuinely shared across several domains (`time.ts`, `business.ts`, etc.) |

### Decision tree for a new literal

1. Does operations change this per environment without a rebuild? → **Env schema.** Read through the project's typed env accessor (e.g. `getEnv()`).
2. Is it a stable rule owned by one feature, service, or route? → `<feature>/constants.ts`.
3. Is it a stable rule genuinely shared across several unrelated domains? → `lib/constants/<concept>.ts`.
4. Does the value appear once, inside one small function or component, with no broader meaning? → Keep inline. Do not lift single-use local literals to module-level `SCREAMING_SNAKE_CASE` constants.
5. Cannot name the owner? → Stop and identify the owner before writing code. "Shared for now" is not an owner.

### Hard rules

- MUST read env values only through the project's typed env accessor. MUST NOT access `process.env.*` directly in feature code.
- MUST scope exported constant names by domain (e.g. `ORDER_RETRY_BASE_DELAY_MS`, `EXPORT_MAX_BODY_LENGTH`). Unscoped names (`BASE_DELAY_MS`, `MAX_BODY_LENGTH`) collide across modules.
- MUST place a one-line JSDoc on every exported constant in the form `NAME reports the …`.
- MUST build copy that references a numeric threshold with a template literal importing the threshold. Never hardcode the number inside the copy string.
- MUST NOT create `src/constants.ts` or a catch-all `src/lib/constants.ts`. The cross-cutting layer is split by concept under `lib/constants/`.
- MUST NOT store JSX fragments or Tailwind class strings in module-level `SCREAMING_SNAKE_CASE` constants. Inline them at the JSX site.
- MUST NOT duplicate the same value across modules. One owns; others import.
- MUST NOT declare an exported module-level constant that no runtime consumer imports. If it exists only to satisfy a test, either inline it in the test or use it in the feature.

### Pattern example

```ts
// lib/constants/time.ts
/** MS_PER_HOUR reports the number of milliseconds in one hour. */
export const MS_PER_HOUR = 60 * MS_PER_MINUTE;

// services/billing/constants.ts
import { MS_PER_HOUR } from '@/lib/constants/time';

/** SUBSCRIPTION_RENEWAL_THRESHOLD_MS reports how far ahead a renewal is attempted. */
export const SUBSCRIPTION_RENEWAL_THRESHOLD_MS = 24 * MS_PER_HOUR;

// app/(dashboard)/deadlines/constants.ts
import { DEADLINE_COMING_UP_DAYS } from '@/lib/constants/business';

/** DEADLINES_COMING_UP_EMPTY_MESSAGE reports the upcoming-section empty-state copy. */
export const DEADLINES_COMING_UP_EMPTY_MESSAGE =
  `No upcoming deadlines in the next ${DEADLINE_COMING_UP_DAYS} days.`;
```

## Data Access Policy

Server Components (`app/**/*.tsx`) delegate database reads to domain query functions. They do not import the database client directly.

### File layout

| File | Role |
|---|---|
| `services/<domain>/<entity>-queries.ts` | Read functions. Single source of SQL for the domain. |
| `services/<domain>/<entity>.ts` (no suffix) | Write services. Called from Server Actions. |
| `lib/actions/<feature>-actions.ts` | Server Actions. Thin; validate input; delegate to write services. |
| `app/<route>/page.tsx` | Authorize → call query → call view-model → render. Never imports the database client directly. |

### Query function rules

- MUST begin with `import 'server-only';`
- MUST accept `userId` (or equivalent tenant key) as the first parameter
- MUST return a DTO shape (serialized non-plain values, flattened relation counts, narrow `select`), not a raw ORM row
- SHOULD wrap in `React.cache()` when the same query is called by `layout.tsx` and `page.tsx` during one request
- MAY use the `'use cache'` directive with `cacheTag` / `cacheLife` when the result is stable longer than one request

### Exception: pure single-row reads

A Server Component MAY call the database client directly only when ALL conditions hold:

1. One `findUnique` or `findFirst` (not `findMany`, not `count`, not raw SQL)
2. Narrow `select` (no `include`, no relation counts)
3. `where` includes `userId` (or equivalent tenant key)
4. No post-processing (no `.toString()`, no `.map()`, no flattening)
5. No sibling query in the same file (no `Promise.all`)

When in doubt, extract.

## File Role Suffixes

| Suffix | Use for | Example |
|---|---|---|
| `-contract.ts` | Shared schema, derived types, and constants for one feature | `order-contract.ts` |
| `-view-model.ts` | Route-scoped normalization and serializable view models | `settings-view-model.ts` |
| `-schemas.ts` | Grouped schemas for one domain or pipeline stage | `import-schemas.ts` |
| `.types.ts` | Feature-scoped pure types when no runtime code belongs in the file | `action.types.ts` |

## ORM Import Policy

Prisma (or another generated ORM client) must be imported only through the project's configured alias — typically `@db` and `@db/*`, or `@/lib/db`. Discover the alias from `tsconfig.json#paths`.

- Never import from a relative path into the generated ORM directory.
- Import runtime enums and the namespace from the alias root.
- Import generated model files from the namespaced subpath only when needed.

```typescript
import type { Prisma } from '@db';
import { OrderStatus, AuditAction } from '@db';
import type { OrderModel } from '@db/models/Order';
```

## React Essentials

- Use named function declarations for React components. Use arrow functions for callbacks and inline utilities.
- Keep `'use client'` on the smallest leaf component that needs hooks, browser APIs, or event handlers.
- Do not store derived values in state.
- Define a named `<ComponentName>Props` interface directly above the component.
- For client mutations, use the project's standard async-action hook (commonly `useAsyncAction`) and reuse the server schema through `zodResolver` instead of redefining form contracts.

## Checklist

- [ ] No `any` without a justified third-party boundary
- [ ] `undefined` for absence; `null` only for external contracts
- [ ] `import type` used for type-only imports
- [ ] No barrel `index.ts` imports inside feature directories
- [ ] New types follow the placement decision tree
- [ ] New constants follow the constants decision tree (env vs feature vs cross-cutting vs inline)
- [ ] Env read through the typed env accessor, never direct `process.env.*`
- [ ] Constant names scoped by domain (`ORDER_RETRY_BASE_DELAY_MS`, not `BASE_DELAY_MS`)
- [ ] UI copy that cites a threshold uses a template literal importing that threshold
- [ ] ORM imports use the configured alias only
- [ ] Client mutations use the project's async-action hook
- [ ] Derived UI state is computed, not stored
