
# Frontend UI Rules

Rules for Tailwind v4 and shadcn/ui usage.

## Tailwind v4

- Tailwind configuration lives in `globals.css` `@theme` blocks. Do not create `tailwind.config.ts`.
- Use design tokens such as `bg-background`, `text-foreground`, and `border-border` instead of raw hex values or arbitrary palette strings unless the file already establishes a custom palette.
- Merge conditional classes with the project's `cn()` utility (typically exported from `@/lib/utils`); do not concatenate Tailwind class strings.
- Use `cva` for components with three or more exclusive visual variants.

```tsx
<div className={cn('rounded-md border px-4 py-2', isPending && 'opacity-50', className)} />
```

## shadcn/ui

- The `components/ui/` directory contains owned shadcn/ui source. Edit primitives directly; do not wrap a primitive only to restyle it once.
- Prefer composition APIs such as `Dialog`, `DialogTrigger`, and `DialogContent` over monolithic prop-driven wrappers.
- Use `asChild` to avoid invalid nested interactive elements.

```tsx
<Button asChild variant="outline">
  <Link href="/dashboard">Open dashboard</Link>
</Button>
```

## Styling Constraints

- Never add CSS-in-JS libraries such as `styled-components` or `@emotion`.
- Keep utility ordering readable and consistent with the file's existing style.
- When a specialised variant is reused in multiple places, create it in a feature component, not in `components/ui/`.
