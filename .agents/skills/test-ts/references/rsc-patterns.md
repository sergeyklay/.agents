# RSC and Next.js module mocking patterns

This file covers mocking recipes for modules that Next.js provides at the server boundary. These mocks are required whenever testing Server Actions, extracted RSC data functions, or any utility that calls `next/navigation`, `next/headers`, `next/cache`, or Auth.js.

All test files in this section MUST use `// @vitest-environment node`.

---

## Table of contents

1. [next/navigation](#1-nextnnavigation)
2. [next/headers](#2-nextheaders)
3. [next/cache](#3-nextcache)
4. [Auth.js session](#4-authjs-session)
5. [Combining multiple mocks](#5-combining-multiple-mocks)
6. [Testing redirect() and notFound()](#6-testing-redirect-and-notfound)

---

## 1. next/navigation

`next/navigation` exports used in Server Actions and RSC data functions: `redirect`, `notFound`, `permanentRedirect`, `useRouter` (Client-only), `usePathname` (Client-only), `useParams`, `useSearchParams`.

### redirect and notFound

```typescript
// @vitest-environment node
import { vi } from 'vitest';

vi.mock('next/navigation', () => ({
  redirect: vi.fn(),
  notFound: vi.fn(),
  permanentRedirect: vi.fn(),
  useRouter: vi.fn(),
  usePathname: vi.fn(() => '/'),
  useParams: vi.fn(() => ({})),
  useSearchParams: vi.fn(() => new URLSearchParams()),
}));
```

### useRouter in Client Component tests (jsdom)

```typescript
import { vi } from 'vitest';

const mockPush = vi.fn();
const mockBack = vi.fn();
const mockReplace = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: vi.fn(() => ({
    push: mockPush,
    back: mockBack,
    replace: mockReplace,
    prefetch: vi.fn(),
    refresh: vi.fn(),
  })),
  usePathname: vi.fn(() => '/invoices'),
  useParams: vi.fn(() => ({ id: 'inv_001' })),
  useSearchParams: vi.fn(() => new URLSearchParams('status=unpaid')),
}));

it('navigates to the invoice detail page on row click', async () => {
  const user = userEvent.setup();
  render(<InvoiceRow invoice={buildInvoice()} />);

  await user.click(screen.getByRole('row'));

  expect(mockPush).toHaveBeenCalledWith('/invoices/inv_test_001');
});
```

---

## 2. next/headers

`next/headers` exports used in server-only code: `headers()`, `cookies()`.

```typescript
// @vitest-environment node
import { vi } from 'vitest';

const mockCookieStore = {
  get: vi.fn(),
  set: vi.fn(),
  delete: vi.fn(),
  has: vi.fn(() => false),
  getAll: vi.fn(() => []),
};

const mockHeaderStore = {
  get: vi.fn(),
  has: vi.fn(() => false),
  entries: vi.fn(() => [][Symbol.iterator]()),
};

vi.mock('next/headers', () => ({
  headers: vi.fn(() => mockHeaderStore),
  cookies: vi.fn(() => mockCookieStore),
}));
```

### Asserting on cookies

```typescript
it('sets the locale cookie when the language preference is saved', async () => {
  const { cookies } = await import('next/headers');
  vi.mocked(cookies).mockReturnValue(mockCookieStore as never);

  await saveLanguagePreference({ locale: 'fr' });

  expect(mockCookieStore.set).toHaveBeenCalledWith('locale', 'fr', expect.objectContaining({ httpOnly: true }));
});
```

### Reading request headers

```typescript
it('rejects requests without a valid X-API-Key header', async () => {
  const { headers } = await import('next/headers');
  vi.mocked(headers).mockReturnValue({
    get: vi.fn((key: string) => (key === 'x-api-key' ? null : undefined)),
  } as never);

  const result = await handleWebhook({ body: '{}' });

  expect(result.success).toBe(false);
  expect(result.error).toMatch(/unauthorized/i);
});
```

---

## 3. next/cache

Mock `revalidateTag` and `unstable_cache` in every Server Action test that calls them.

```typescript
vi.mock('next/cache', () => ({
  revalidateTag: vi.fn(),
  revalidatePath: vi.fn(),
  unstable_cache: vi.fn((fn: (...args: unknown[]) => unknown) => fn),
}));
```

Verify cache invalidation as part of the mutation contract:

```typescript
it('revalidates the invoices tag after a successful payment', async () => {
  const { revalidateTag } = await import('next/cache');
  // ... arrange mocks
  await markInvoicePaid({ invoiceId: 'inv_001', paidAt: new Date() });
  expect(revalidateTag).toHaveBeenCalledWith('invoices');
});
```

---

## 4. Auth.js session

The project uses Auth.js with the Prisma adapter (ADR-0005). The `auth()` function is imported from the project-level configuration at `@/lib/auth`. Mock it at that path.

```typescript
// @vitest-environment node
import { vi } from 'vitest';

import type { Session } from 'next-auth';

const mockSession: Session = {
  user: { id: 'user_test_001', email: 'test@example.com', name: 'Test User' },
  expires: new Date(Date.now() + 3_600_000).toISOString(),
};

vi.mock('@/lib/auth', () => ({
  auth: vi.fn(() => Promise.resolve(mockSession)),
}));
```

### Testing unauthenticated access

```typescript
it('redirects to /login when the session is null', async () => {
  const { auth } = await import('@/lib/auth');
  const { redirect } = await import('next/navigation');
  vi.mocked(auth).mockResolvedValue(null);

  await getInvoicesForUser();

  expect(redirect).toHaveBeenCalledWith('/login');
});
```

### Scoping session overrides per test

```typescript
describe('getInvoiceById', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(auth).mockResolvedValue(mockSession);  // default: authenticated
  });

  it('returns the invoice when the session user owns it', async () => { ... });

  it('throws ForbiddenError when the session user does not own it', async () => {
    vi.mocked(auth).mockResolvedValue({ ...mockSession, user: { id: 'other_user' } } as Session);
    // ...
  });
});
```

---

## 5. Combining multiple mocks

Server Actions commonly need several Next.js modules mocked together. Define a shared mock setup at the top of the test file.

```typescript
// @vitest-environment node
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Session } from 'next-auth';

import { createInvoice } from '@/lib/actions/invoice-actions';

vi.mock('@/lib/db', () => ({ db: { invoice: { create: vi.fn() } } }));
vi.mock('@/lib/auth', () => ({ auth: vi.fn() }));
vi.mock('next/cache', () => ({ revalidateTag: vi.fn() }));
vi.mock('next/navigation', () => ({ redirect: vi.fn() }));

describe('createInvoice', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    const { auth } = await import('@/lib/auth');
    vi.mocked(auth).mockResolvedValue({
      user: { id: 'user_001' },
      expires: '',
    } as Session);
  });

  it('creates the invoice and revalidates the cache', async () => {
    const { db } = await import('@/lib/db');
    const { revalidateTag } = await import('next/cache');
    vi.mocked(db.invoice.create).mockResolvedValue(buildInvoice());

    const result = await createInvoice({ clientName: 'Acme', amount: 1000 });

    expect(result).toEqual({ success: true });
    expect(revalidateTag).toHaveBeenCalledWith('invoices');
  });
});
```

---

## 6. Testing redirect() and notFound()

In Next.js App Router, `redirect()` and `notFound()` throw specially typed errors internally. When mocked with `vi.fn()`, they do nothing by default. If the code under test depends on execution stopping after a `redirect()` or `notFound()` call, mock them to throw:

```typescript
vi.mock('next/navigation', () => ({
  redirect: vi.fn().mockImplementation((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`);
  }),
  notFound: vi.fn().mockImplementation(() => {
    throw new Error('NEXT_NOT_FOUND');
  }),
}));

it('throws a redirect to /login when the user is unauthenticated', async () => {
  vi.mocked(auth).mockResolvedValue(null);

  await expect(getProtectedData()).rejects.toThrow('NEXT_REDIRECT:/login');
});
```

Use this pattern only when the test needs to verify that execution stops at the redirect/notFound call. For tests that only need to assert the call happened (not that execution stopped), `vi.fn()` without the throw is sufficient.
