
# Next.js App Router Rules

Rules for App Router code.

## Server and Client Boundary

- Files under `app/` are Server Components by default.
- Add `'use client'` only when the file uses hooks, browser APIs, or direct event handlers.
- Never add `'use client'` to a page or layout when a leaf component is sufficient.
- Server Components read data directly through the project's database client or service layer. Do not create `/api/` routes for data a Server Component can query directly.

## Server Actions

- Server Actions live in a dedicated actions directory (commonly `lib/actions/`) and begin with `'use server'`.
- Call the project's session helper (e.g. `await auth()`) before user-scoped work.
- Validate every input with the project's schema validator (`schema.safeParse()` for Zod) before database or external API calls.
- Return a typed result wrapper (commonly `ActionResult<T>` from a shared action types module).
- Do not expose raw ORM errors or service-layer return types to clients.
- Export shared action schemas and derived input types from the action file, or from a colocated `<feature>-contract.ts` when multiple modules share them.
- Keep DTO names distinct from service-layer result names.

## Route-Scoped Types

- Route-specific normalization lives in `*-view-model.ts` files inside the route segment.
- Types that cross from a Server Component or Server Action into a client component must be serializable.
- Convert non-plain values (e.g. `Prisma.Decimal`, `Date` where appropriate) to strings or numbers at the boundary.

## Rendering and Caching

- Render dates with a hydration-stable client component (e.g. `<ClientDate />`) so server- and client-rendered output match.
- Use the `'use cache'` directive for cached data functions.
- Do not use `cache: 'force-cache'` or `export const revalidate` for ad-hoc caching - prefer `'use cache'` with explicit tags.
- After mutations, invalidate cached reads with `revalidateTag()`.

## Reading Data

- Pages and layouts call exactly one query function per screen, imported from a domain module (commonly `services/<domain>/<entity>-queries.ts`).
- Query functions take `userId` (or the equivalent tenant key) as the first argument and return DTOs ready for client serialization.
- The `'use cache'` directive goes on the query function, not the page. Use `cacheTag(\`<entity>:${userId}\`)` for user-scoped invalidation.
- `revalidateTag()` belongs in Server Actions that mutate the underlying data.
