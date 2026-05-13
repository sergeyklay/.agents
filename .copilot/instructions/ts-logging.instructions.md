---
description: 'Structured logging discipline for Node.js services using pino: call-site patterns, log levels, security redaction, and environment behaviour.'
applyTo: '**/*.ts,**/*.tsx'
---

# Logging & Observability

When the project uses [pino](https://github.com/pinojs/pino) (or another structured JSON logger), follow these rules. The principles transfer to other libraries; the pino-specific snippets show the expected shape.

## 1. No Console Logs

- **FORBIDDEN:** `console.log`, `console.error`, `console.warn` in application code.
- **REQUIRED:** Use the project's logger module (commonly `@/lib/logger` or similar).
- **ENFORCEMENT:** ESLint `no-console` set to `error`. Test setup files may mock console.

## 2. Logger Setup

Initialize a child logger with the current module context at the top of every file. The factory creates a child logger with `{ module: <context> }`, so every entry carries its origin without repetition at call sites.

```typescript
import { getLogger } from '@/lib/logger';

const logger = getLogger('UserService'); // Context name is mandatory
```

Use PascalCase names that match the service, component, or pipeline stage - e.g. `UserService`, `PaymentService`, `OAuthService`, `WorkflowRunner`, `IngestPipeline`.

## 3. Logging Patterns

### Simple message (no data)

```typescript
logger.info('Starting batch run...');
logger.warn('No matching records found');
```

### Message with structured data

Object first, message second. The logger merges the object into the JSON entry:

```typescript
// ✅ Correct
logger.info({ requestId, userId }, 'Request handled');
logger.debug({ query, durationMs: 42 }, 'Database query executed');

// ❌ Wrong: string interpolation defeats structured logging
logger.info('Request ' + requestId + ' handled');
logger.info(`Request ${requestId} handled`);
```

### Error logging

Pass the `Error` object directly as the first argument. pino's built-in error serializer extracts `message`, `stack`, `type`, and `code` automatically:

```typescript
try {
  await doWork(jobId);
} catch (error) {
  // ✅ Correct: Error as first argument
  logger.error(error, 'Job failed');
}
```

```typescript
// ❌ Wrong: wraps error in object with the wrong key
logger.error({ error }, 'Job failed');

// ❌ Wrong: only message, no error object
logger.error('Job failed');
```

### Error with additional context

Use the `err` key when including extra data alongside the error:

```typescript
catch (error) {
  // ✅ Correct: error under 'err' key with extra context
  logger.error({ err: error, jobId, userId, attempt }, 'Job failed');
}
```

## 4. Log Levels

| Level | Use Case | Example |
|---|---|---|
| `fatal` | System unusable, crash imminent | DB connection lost, worker thread died |
| `error` | Operation failed, app continues | Job failed, external API returned 5xx |
| `warn` | Unexpected but handled | Rate limit hit, retry succeeded |
| `info` | Lifecycle events | Service started, batch complete |
| `debug` | Development details | Query results, internal scoring |
| `trace` | Extremely verbose | Per-element loop iteration |

## 5. Security: Sensitive Data Redaction

Tokens, credentials, raw user content, and unredacted PII are never logged. Register custom serializers (pino: `serializers` option, or `redact` paths) at the logger boundary so accidents at call sites don't leak.

```typescript
// ❌ FORBIDDEN: tokens, raw payloads, full PII
logger.info({ accessToken }, 'Token refreshed');
logger.debug({ body: rawPayload }, 'Processing request');

// ✅ Correct: log only safe identifiers and metadata
logger.info({ userId, provider: 'google' }, 'Token refreshed');
logger.debug({ requestId, contentLength: rawPayload.length }, 'Processing request');
```

When adding a `logger.*` call that passes a domain object, verify no sensitive field (tokens, passwords, raw user content, financial figures) is included. Register a custom serializer for new types that contain PII.

## 6. Environment Behaviour

- **Server (production):** Newline-delimited JSON to `stdout`. The runtime captures and ships logs. No file-based transports, log rotation, or sidecar collectors.
- **Server (development):** `pino-pretty` (or equivalent) for colorized, human-readable output. Same code path as production; only the transport differs.
- **Client (development):** Logs to browser console via a thin adapter.
- **Client (production):** Only `error` and `fatal`. Never log PII, tokens, or financial data on the client.
