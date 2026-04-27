/**
 * Vitest configuration for {project name} (Next.js {version} App Router project).
 *
 * Environment strategy:
 *   - Default: jsdom  (React Testing Library, Client Components)
 *   - Override per file: // @vitest-environment node  (Server Actions, utilities)
 *
 * Usage: copy this file to the project root as vitest.config.ts
 * and adjust the alias paths to match your tsconfig.json paths.
 */
import path from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],

  resolve: {
    alias: {
      // Must match tsconfig.json paths exactly.
      // Add or remove aliases to match your tsconfig.
      "@": path.resolve(import.meta.dirname, "./src"),
    },
  },

  test: {
    // jsdom provides browser-like globals for React Testing Library.
    // Server Action tests override this with: // @vitest-environment node
    environment: "jsdom",

    // Runs before each test file. Imports @testing-library/jest-dom matchers
    // (.toBeInTheDocument(), .toHaveClass(), .toBeDisabled(), etc.).
    setupFiles: ["./vitest.setup.ts"],

    // Include only test files in src/. Excludes e2e tests, which live in tests/.
    include: ["src/**/*.test.ts", "src/**/*.test.tsx", "*.test.ts"],
    exclude: ["tests/**", "node_modules/**", ".next/**"],

    // Inline CSS modules and static asset imports so components render without errors.
    css: true,

    // Coverage configuration; run with: npm run test:coverage
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "lcov"],
      include: ["src/**/*.ts", "src/**/*.tsx"],
      exclude: [
        "src/**/*.test.ts",
        "src/**/*.test.tsx",
        "src/**/*.d.ts",
        "src/__fixtures__/**",
        "src/components/ui/**", // shadcn/ui components are owned but generated
        "src/types/**",
        "src/app/**/page.tsx", // RSC page shells tested via E2E, not unit tests
        "src/app/**/layout.tsx",
        "src/app/**/loading.tsx",
        "src/app/**/error.tsx",
        "src/app/**/not-found.tsx",
      ],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 75,
        statements: 80,
      },
    },

    // Globals: false. Always import { describe, it, expect, vi } from 'vitest' explicitly.
    // This prevents naming collisions and keeps imports explicit.
    globals: false,
  },
});
