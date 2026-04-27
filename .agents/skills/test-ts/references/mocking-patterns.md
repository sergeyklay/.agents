# Prisma and module mocking patterns

This file covers Prisma 7 mock chains, complex relation patterns, `$transaction`, and recipes for other project-specific modules (Zod forms, `useAsyncAction`). Load this reference when the SKILL.md main body patterns are insufficient for a specific mock scenario.

---

## Table of contents

1. [Prisma client setup](#1-prisma-client-setup)
2. [Basic CRUD mocks](#2-basic-crud-mocks)
3. [Chained query methods](#3-chained-query-methods)
4. [Relations and nested includes](#4-relations-and-nested-includes)
5. [$transaction mocks](#5-transaction-mocks)
6. [Simulating Prisma errors](#6-simulating-prisma-errors)
7. [Testing forms with Zod + React Hook Form](#7-testing-forms-with-zod--react-hook-form)
8. [Testing useAsyncAction](#8-testing-useasyncaction)

---

## 1. Prisma client setup

Mock the entire Prisma client at the module boundary. Never import the real `db` instance in unit or component tests.

```typescript
// @vitest-environment node
import { vi, beforeEach } from 'vitest';

vi.mock('@/lib/db', () => ({
  db: {
    invoice: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      upsert: vi.fn(),
      delete: vi.fn(),
      count: vi.fn(),
    },
    contact: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    user: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
    $transaction: vi.fn(),
  },
}));
```

Call `vi.clearAllMocks()` in `beforeEach` to prevent call counts and resolved values from bleeding between tests.

### Typed access

Always access mocked methods through `vi.mocked()` rather than casting to `any`:

```typescript
const { db } = await import('@/lib/db');

// ✅
vi.mocked(db.invoice.findMany).mockResolvedValue([buildInvoice()]);

// ❌
(db.invoice.findMany as jest.Mock).mockResolvedValue([]);  // Jest API, wrong in Vitest
(db.invoice.findMany as unknown as ReturnType<typeof vi.fn>).mockResolvedValue([]); // fragile
```

---

## 2. Basic CRUD mocks

### findMany

```typescript
vi.mocked(db.invoice.findMany).mockResolvedValue([
  buildInvoice({ id: 'inv_001', status: 'unpaid' }),
  buildInvoice({ id: 'inv_002', status: 'paid' }),
]);
```

### findUnique: found and not found

```typescript
// Found
vi.mocked(db.invoice.findUnique).mockResolvedValue(buildInvoice({ id: 'inv_001' }));

// Not found: returns null per Prisma 7 contract
vi.mocked(db.invoice.findUnique).mockResolvedValue(null);
```

### create

```typescript
const created = buildInvoice({ id: 'inv_new_001', createdAt: new Date() });
vi.mocked(db.invoice.create).mockResolvedValue(created);
```

### update

```typescript
vi.mocked(db.invoice.update).mockResolvedValue(
  buildInvoice({ id: 'inv_001', status: 'paid', paidAt: new Date('2026-03-01') })
);
```

### count

```typescript
vi.mocked(db.invoice.count).mockResolvedValue(42);
```

---

## 3. Chained query methods

Some Prisma query builders return chainable objects. Mock the chain by returning an object with the expected methods.

### aggregate

```typescript
vi.mocked(db.invoice.aggregate).mockResolvedValue({
  _sum: { amount: 15000 },
  _count: { id: 10 },
  _avg: { amount: 1500 },
  _min: { amount: 100 },
  _max: { amount: 5000 },
});
```

### groupBy

```typescript
vi.mocked(db.invoice.groupBy).mockResolvedValue([
  { status: 'paid',    _sum: { amount: 12000 }, _count: { id: 8 } },
  { status: 'unpaid',  _sum: { amount: 3000 },  _count: { id: 2 } },
]);
```

---

## 4. Relations and nested includes

When the function under test expects Prisma to return a record with included relations, the mock must return the full shape.

```typescript
// Type reflecting the query: db.invoice.findUnique({ include: { contact: true, items: true } })
import type { Prisma } from '@prisma/client';

type InvoiceWithRelations = Prisma.InvoiceGetPayload<{
  include: { contact: true; items: true };
}>;

export function buildInvoiceWithRelations(
  overrides: Partial<InvoiceWithRelations> = {}
): InvoiceWithRelations {
  return {
    ...buildInvoice(),
    contact: {
      id: 'contact_001',
      name: 'Acme Corp',
      email: 'billing@acme.com',
      userId: 'user_test_001',
      createdAt: new Date('2026-01-01'),
    },
    items: [
      { id: 'item_001', invoiceId: 'inv_test_001', description: 'Consulting', amount: 1000, quantity: 1 },
    ],
    ...overrides,
  };
}

// In the test
vi.mocked(db.invoice.findUnique).mockResolvedValue(buildInvoiceWithRelations());
```

---

## 5. $transaction mocks

Prisma's `$transaction` accepts either an array of promises or an interactive callback. Mock both forms.

### Array form

```typescript
vi.mocked(db.$transaction).mockImplementation(async (operations: Promise<unknown>[]) => {
  return Promise.all(operations);
});
```

### Callback form (interactive transaction)

```typescript
vi.mocked(db.$transaction).mockImplementation(async (fn: (tx: typeof db) => Promise<unknown>) => {
  // Pass the mocked db as the transaction client
  const { db } = await import('@/lib/db');
  return fn(db);
});
```

The callback form passes the transaction client (`tx`) to the callback. Because `db` is already mocked, passing it directly as `tx` lets the callback's internal calls resolve through the same mocks.

### Verifying operations within a transaction

```typescript
it('creates the invoice and the audit log within a single transaction', async () => {
  vi.mocked(db.invoice.create).mockResolvedValue(buildInvoice());
  vi.mocked(db.auditLog.create).mockResolvedValue({ id: 'log_001', invoiceId: 'inv_001', action: 'created' });

  await createInvoiceWithAudit({ clientName: 'Acme', amount: 1000 });

  expect(db.$transaction).toHaveBeenCalledOnce();
  expect(db.invoice.create).toHaveBeenCalledOnce();
  expect(db.auditLog.create).toHaveBeenCalledOnce();
});
```

---

## 6. Simulating Prisma errors

### Record not found (P2025)

```typescript
import { Prisma } from '@prisma/client';

vi.mocked(db.invoice.update).mockRejectedValue(
  new Prisma.PrismaClientKnownRequestError('Record not found', {
    code: 'P2025',
    clientVersion: '7.0.0',
  })
);

it('returns a not-found error result when the invoice does not exist', async () => {
  const result = await markInvoicePaid({ invoiceId: 'missing_id', paidAt: new Date() });

  expect(result.success).toBe(false);
  expect(result.error).toMatch(/not found/i);
});
```

### Unique constraint violation (P2002)

```typescript
vi.mocked(db.invoice.create).mockRejectedValue(
  new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
    code: 'P2002',
    clientVersion: '7.0.0',
    meta: { target: ['invoiceNumber'] },
  })
);
```

### Database connection failure

```typescript
vi.mocked(db.invoice.findMany).mockRejectedValue(
  new Prisma.PrismaClientInitializationError('Connection refused', '7.0.0')
);
```

---

## 7. Testing forms with Zod + React Hook Form

For Client Components that use `useForm` with `zodResolver` and submit via `useAsyncAction`, test the form by interacting through the UI. Do not call form methods directly.

```typescript
// Component: CreateInvoiceForm
// - imports markInvoicePaidSchema from '@/lib/actions/invoice-actions'
// - uses zodResolver(markInvoicePaidSchema)
// - submits via useAsyncAction({ action: createInvoice })

const mockCreateInvoice = vi.fn();
vi.mock('@/lib/actions/invoice-actions', () => ({
  createInvoice: mockCreateInvoice,
  createInvoiceSchema: actualSchema,  // keep real schema so validation runs in the test
}));

it('calls createInvoice with validated data when the form is submitted', async () => {
  const user = userEvent.setup();
  mockCreateInvoice.mockResolvedValue({ success: true });

  render(<CreateInvoiceForm />);
  await user.type(screen.getByLabelText('Client name'), 'Acme Corp');
  await user.type(screen.getByLabelText('Amount'), '1500');
  await user.click(screen.getByRole('button', { name: /create invoice/i }));

  expect(mockCreateInvoice).toHaveBeenCalledWith(
    expect.objectContaining({ clientName: 'Acme Corp', amount: 1500 })
  );
});

it('displays validation errors without submitting when required fields are empty', async () => {
  const user = userEvent.setup();

  render(<CreateInvoiceForm />);
  await user.click(screen.getByRole('button', { name: /create invoice/i }));

  expect(screen.getByText(/client name is required/i)).toBeInTheDocument();
  expect(mockCreateInvoice).not.toHaveBeenCalled();
});
```

Key point: import the real Zod schema in the mock so validation runs in the test environment. Only mock the action function, not the schema.

---

## 8. Testing useAsyncAction

`useAsyncAction` from `@/lib/hooks/use-async-action` wraps a Server Action with loading state and toast feedback. Test it by mocking the action it wraps and observing the `isPending` / `isSuccess` state transitions.

```typescript
import { renderHook, act } from '@testing-library/react';
import { vi, describe, it, expect } from 'vitest';

import { useAsyncAction } from '@/lib/hooks/use-async-action';

describe('useAsyncAction', () => {
  it('sets isPending to true during execution and false after success', async () => {
    const action = vi.fn().mockResolvedValue({ success: true });

    const { result } = renderHook(() => useAsyncAction({ action }));

    expect(result.current.isPending).toBe(false);

    let executePromise: Promise<void>;
    act(() => { executePromise = result.current.execute(); });

    expect(result.current.isPending).toBe(true);

    await act(() => executePromise);

    expect(result.current.isPending).toBe(false);
  });

  it('calls onSuccess when the action resolves with success: true', async () => {
    const onSuccess = vi.fn();
    const action = vi.fn().mockResolvedValue({ success: true, data: { id: 'inv_001' } });

    const { result } = renderHook(() => useAsyncAction({ action, onSuccess }));
    await act(() => result.current.execute());

    expect(onSuccess).toHaveBeenCalledWith({ id: 'inv_001' });
  });

  it('does not call onSuccess when the action returns success: false', async () => {
    const onSuccess = vi.fn();
    const action = vi.fn().mockResolvedValue({ success: false, error: 'Not found' });

    const { result } = renderHook(() => useAsyncAction({ action, onSuccess }));
    await act(() => result.current.execute());

    expect(onSuccess).not.toHaveBeenCalled();
  });
});
```
