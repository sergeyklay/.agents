/**
 * Vitest global setup file for {project name}.
 *
 * Referenced by vitest.config.ts → test.setupFiles.
 * Runs once before each test file, after the test framework initializes.
 */
import "@testing-library/jest-dom/vitest";

/**
 * Silence Next.js router errors in jsdom tests.
 *
 * RTL tests that render components using next/navigation will log console
 * errors unless the router is mocked. Suppress the specific Next.js warning
 * here; each test file that needs next/navigation should mock it explicitly.
 */
const originalError = console.error.bind(console);
beforeAll(() => {
  console.error = (...args: unknown[]) => {
    const message = typeof args[0] === "string" ? args[0] : "";
    // Suppress Next.js router context warnings in unit tests
    if (message.includes("useRouter") || message.includes("next/navigation"))
      return;
    originalError(...args);
  };
});

afterAll(() => {
  console.error = originalError;
});
