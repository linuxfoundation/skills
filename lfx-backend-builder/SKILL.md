---
name: lfx-backend-builder
description: >
  Generate compliant backend code for LFX repos — Express.js proxy endpoints
  (lfx-v2-ui) or Go microservice code (resource services). Encodes the three-file
  pattern, logging conventions, Goa DSL, NATS messaging, and microservice proxy usage.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->
<!-- Tool names in this file use Claude Code vocabulary. See docs/tool-mapping.md for other platforms. -->

# LFX Backend Code Generation

You are generating backend code that must be PR-ready. This skill adapts to the repo type and encodes all backend conventions.

**Prerequisites:** Upstream API contracts must be validated first (via `/lfx-research`).

## Input Validation

Before generating any code, verify your args include:

| Required | If Missing |
|----------|------------|
| Specific task (what to build/modify) | Stop and ask — do not guess |
| Absolute repo path | Stop and ask — never assume cwd |
| File paths to create/modify | Infer from domain, but verify they exist |
| Example pattern to follow | Find one yourself (see Read Before Generating) |

**If invoked with a FIX: prefix**, this is an error correction from the coordinator. Read the error, find the file, apply the targeted fix, and re-validate.

## Read Before Generating — MANDATORY

Before writing ANY code, you MUST:

1. **Read the target file** (if modifying) — understand what's already there
2. **Read one example file** in the same domain — match the exact patterns
3. **Read the relevant interface file** — ensure types match
4. **Read `docs/indexer-contract.md`** (if it exists in the target service repo and the task touches indexing) — authoritative source for data schemas, tags, access control, and parent references

Do NOT generate code from memory alone. The codebase may have evolved since your training data.

```bash
# Example: before modifying committee.service.ts, read it first
cat apps/lfx-one/src/server/services/committee.service.ts
# And read the interface
cat packages/shared/src/interfaces/member.interface.ts
```

## License Header

Every new `.ts` file MUST start with this header:

```typescript
// Copyright The Linux Foundation and each contributor to LFX.
// SPDX-License-Identifier: MIT
```

Every new `.go` file MUST start with:

```go
// Copyright The Linux Foundation and each contributor to LFX.
// SPDX-License-Identifier: MIT
```

## Completion Report

When you finish, output a clear summary so the caller (usually `/lfx-coordinator`) and the user can see what happened:

```
═══════════════════════════════════════════
/lfx-backend-builder COMPLETE
═══════════════════════════════════════════
Files created:
  - (none)

Files modified:
  - packages/shared/src/interfaces/member.interface.ts — added bio field
  - apps/lfx-one/src/server/services/committee.service.ts — no changes needed (pass-through)

Validation:
  - Ran: yarn format (if in Angular repo)
  - Result: ✓ passed / ✗ failed with: <error>

Notes:
  - Express proxy is pass-through, no field-level changes required

Errors:
  - (none)
═══════════════════════════════════════════
```

**Always include the Validation section.** Run `yarn format` after modifying files in the Angular repo, or `go vet ./...` in Go repos. Report the result.

## Repo Type Detection

```bash
if [ -f apps/lfx-one/angular.json ] || [ -f turbo.json ]; then
  echo "REPO_TYPE=angular"      # Express.js proxy layer
elif [ -f go.mod ]; then
  echo "REPO_TYPE=go"           # Go microservice
fi
```

---

## Express.js Proxy (Angular Repo — lfx-v2-ui)

The Express.js backend is a thin proxy layer — shapes must match upstream Go microservices.

### Upstream Microservice References

These references document the Go microservice platform that the Express.js proxy layer connects to. Read the relevant reference when working with upstream APIs.

| Task | Reference |
| --- | --- |
| Repo map, deployment overview, local dev setup, where to start | [references/getting-started.md](references/getting-started.md) |
| NATS subject naming, service-to-service communication, KV storage | [references/nats-messaging.md](references/nats-messaging.md) |
| Goa DSL conventions, `make apigen`, adding fields, ETag / If-Match pattern | [references/goa-patterns.md](references/goa-patterns.md) |
| Indexer message payload, `IndexingConfig` schema, OpenSearch doc structure | [references/indexer-patterns.md](references/indexer-patterns.md) |
| OpenFGA tuples, generic fga-sync handlers, permission inheritance, debugging access | [references/fga-patterns.md](references/fga-patterns.md) |
| Native vs wrapper service types, which template to follow | [references/service-types.md](references/service-types.md) |
| Query service API, how it queries OpenSearch and checks access via fga-sync | [references/query-service.md](references/query-service.md) |
| Service Helm chart — deployment, HTTPRoute, Heimdall ruleset, KV buckets, secrets | [references/helm-chart.md](references/helm-chart.md) |
| Building a new resource service end-to-end | [references/new-service.md](references/new-service.md) |

### 1. Three-File Pattern

Every backend endpoint creates three files in strict order: **service** -> **controller** -> **route**.

#### Service (`src/server/services/<name>.service.ts`)

The service handles business logic, upstream API calls via `MicroserviceProxyService`, and response transformation.

```typescript
// Copyright The Linux Foundation and each contributor to LFX.
// SPDX-License-Identifier: MIT

import { QueryServiceResponse, MyItem, PaginatedResponse } from '@lfx-one/shared/interfaces';
import { Request } from 'express';

import { logger } from './logger.service';
import { MicroserviceProxyService } from './microservice-proxy.service';

class MyService {
  private microserviceProxy: MicroserviceProxyService;

  constructor() {
    this.microserviceProxy = new MicroserviceProxyService();
  }

  // READ — query service via /query/resources
  public async getItems(req: Request, query: Record<string, any> = {}): Promise<PaginatedResponse<MyItem>> {
    logger.debug(req, 'get_items', 'Fetching items from query service', { query });

    const { resources, page_token } = await this.microserviceProxy.proxyRequest<QueryServiceResponse<MyItem>>(
      req,
      'LFX_V2_SERVICE',
      '/query/resources',
      'GET',
      { ...query, type: 'my_item' }
    );

    const items = resources.map((r: any) => r.data);
    logger.debug(req, 'get_items', 'Fetched items', { count: items.length });
    return { data: items, page_token };
  }

  // WRITE — via /itx/... endpoints
  public async createItem(req: Request, payload: Partial<MyItem>): Promise<MyItem> {
    logger.debug(req, 'create_item', 'Creating item', { payload });

    const result = await this.microserviceProxy.proxyRequest<MyItem>(req, 'LFX_V2_SERVICE', '/itx/items', 'POST', payload);

    return result;
  }
}

export const myService = new MyService();
```

**Service rules:**

- `MicroserviceProxyService` for ALL external API calls (no raw `fetch`/`axios`)
- Reads: `/query/resources` with `type` parameter
- Writes: `/itx/...` endpoints matching upstream service paths
- `logger.debug()` for step-by-step tracing
- `logger.info()` for significant operations (V1->V2 transforms, enrichment)
- `logger.warning()` for recoverable errors (returning null/empty)
- NEVER use `serverLogger` directly — always use `logger` from `logger.service`

#### Controller (`src/server/controllers/<name>.controller.ts`)

The controller is the HTTP boundary — validation, logging lifecycle, and response.

```typescript
// Copyright The Linux Foundation and each contributor to LFX.
// SPDX-License-Identifier: MIT

import { NextFunction, Request, Response } from 'express';

import { validateUidParameter } from '../helpers/validation.helper';
import { logger } from '../services/logger.service';
import { myService } from '../services/my.service';

export const getItems = async (req: Request, res: Response, next: NextFunction) => {
  const startTime = logger.startOperation(req, 'get_items', {});

  try {
    const items = await myService.getItems(req, req.query);
    logger.success(req, 'get_items', startTime, { count: items.data.length });
    return res.json(items);
  } catch (error) {
    logger.error(req, 'get_items', startTime, error, {});
    return next(error);
  }
};
```

**Controller rules:**

- `logger.startOperation()` -> `try/catch` -> `logger.success()` or `logger.error()` + `next(error)`
- NEVER use `res.status(500).json()` — always `next(error)` for centralized error handling
- Operation names in `snake_case`
- Use `validateUidParameter` from helpers for parameter validation
- One `startOperation` per HTTP endpoint — never duplicate in services

#### Route (`src/server/routes/<name>.route.ts`)

```typescript
// Copyright The Linux Foundation and each contributor to LFX.
// SPDX-License-Identifier: MIT

import { Router } from 'express';
import { getItems, getItemById, createItem } from '../controllers/my.controller';

const router = Router();

router.get('/', getItems);
router.get('/:uid', getItemById);
router.post('/', createItem);

export default router;
```

**Route registration:** The route must be registered in `server.ts`, which is a **protected file**. Tell the contributor:

> "The route file is created, but it needs to be registered in `server.ts`. Since that's a protected infrastructure file, please ask a code owner to add the route registration."

### 2. Logging

Follow the logging patterns rule for full details. Summary:

| Layer | Pattern | When |
|-------|---------|------|
| **Controller** | `logger.startOperation/success/error` with `startTime` | Every HTTP endpoint |
| **Service** | `logger.debug()` | Step-by-step tracing |
| **Service** | `logger.info()` | Significant ops (transforms, enrichment) |
| **Service** | `logger.warning()` | Recoverable errors (returning null/empty) |
| **Infrastructure** | Pass `undefined` for `req` | Startup, NATS, Snowflake |

### 3. Error Handling

- Use `MicroserviceError.fromMicroserviceResponse()` for upstream failures
- Use `ServiceValidationError.forField()` for input validation
- NEVER `res.status(500).json()` — always `next(error)`

### 4. Authentication

**Default: Use the user's bearer token** (`req.bearerToken`). M2M tokens only for public endpoints or privileged upstream calls after user authorization is verified.

### 5. Pagination

- Single-page: Return `PaginatedResponse<T>` with `page_token`
- All-pages: Use `fetchAllQueryResources` helper
- Use `page_size` (not `limit`), conditional `page_token` spread

### Common Anti-Patterns — DO NOT DO THESE

| Anti-Pattern | Correct Pattern |
|-------------|-----------------|
| `import { serverLogger }` | `import { logger } from './logger.service'` |
| `res.status(500).json({ error })` | `next(error)` |
| `fetch('http://...')` or `axios.get(...)` | `this.microserviceProxy.proxyRequest(...)` |
| `const x = req.body.field \|\| ''` | Use validation helpers |
| Hardcoded upstream URLs | Environment variable via `MicroserviceProxyService` |
| `console.log(...)` | `logger.debug(req, ...)` |

### Express.js Checklist

- [ ] Three files created: service -> controller -> route
- [ ] License header on all files
- [ ] Service uses `MicroserviceProxyService` (not raw `fetch`/`axios`)
- [ ] Service uses `logger` service (not `serverLogger`)
- [ ] Controller uses `logger.startOperation()` / `logger.success()` / `logger.error()`
- [ ] Controller passes errors to `next(error)` (not `res.status(500)`)
- [ ] Controller uses validation helpers for parameter validation
- [ ] Operation names in `snake_case`
- [ ] Authentication defaults to user bearer token
- [ ] Pagination uses `page_size` (not `limit`)

---

## Go Microservice (Resource Service Repos)

For Go microservice repos (`lfx-v2-*-service`), follow the platform conventions.

### Code Structure

```text
cmd/{service}-api/
├── design/           ← Goa DSL (API contract)
│   ├── {service}.go  ← API, Service, Method definitions
│   └── type.go       ← Type definitions, attribute functions
├── service/          ← API handler implementation
└── main.go

internal/
├── domain/
│   ├── model/        ← Domain structs with Tags() method
│   └── port/         ← Reader/writer/publisher interfaces
├── infrastructure/
│   └── nats/
│       ├── client.go         ← NATS connection + KV bucket init
│       ├── storage.go        ← KV CRUD with optimistic locking
│       └── messaging_publish.go  ← Index + access message publishing
└── service/
    ├── {resource}_writer.go  ← Orchestrates writes
    └── {resource}_reader.go  ← Read operations

gen/                  ← GENERATED — never edit (make apigen)
charts/               ← Helm chart for deployment
```

### Key Patterns

**Goa API Design:** Define endpoints in `cmd/{service}/design/`. Run `make apigen` to regenerate `gen/`. See [references/goa-patterns.md](references/goa-patterns.md).

**NATS Messaging:** Publish index + access messages on every write. See [references/nats-messaging.md](references/nats-messaging.md) and [references/indexer-patterns.md](references/indexer-patterns.md).

**FGA Access Control:** Use generic fga-sync handlers for access tuples. See [references/fga-patterns.md](references/fga-patterns.md).

**Service Types:** Native services own data in NATS KV. Wrapper services proxy to external systems. See [references/service-types.md](references/service-types.md).

**Helm Chart:** One rule per Goa endpoint in `ruleset.yaml`. See [references/helm-chart.md](references/helm-chart.md).

### Common Anti-Patterns — DO NOT DO THESE (Go)

| Anti-Pattern | Correct Pattern |
|-------------|-----------------|
| Editing files in `gen/` | Run `make apigen` to regenerate |
| Hardcoding NATS subjects | Use subject constants from shared package |
| Missing `Tags()` on domain model | Always implement — used for OpenSearch indexing |
| Missing index message on writes | Publish on every create, update, delete |
| HTTP calls between services | Use NATS request/reply |

### Go Checklist

- [ ] License header on all new `.go` files
- [ ] Goa design follows conventions (`type.go` + `{service}.go`)
- [ ] `make apigen` runs cleanly
- [ ] Domain model has `Tags()` method
- [ ] Index message published on every write (create, update, delete)
- [ ] Access message published if resource has FGA type
- [ ] `docs/indexer-contract.md` (if present) updated if indexing behavior changed (same PR)
- [ ] Optimistic locking via revision (native services)
- [ ] Health endpoints (`/livez`, `/readyz`) implemented
- [ ] Helm chart updated (ruleset, httproute if new paths)
- [ ] Queue group subscriptions for all NATS handlers

## Scope Boundaries

**This skill DOES:**
- Generate/modify backend code (Express.js or Go)
- Add shared types in `packages/shared/`
- Run format/lint validation after changes

**This skill does NOT:**
- Generate Angular components, templates, or frontend services (use `/lfx-ui-builder`)
- Make architectural decisions (use `/lfx-product-architect`)
- Modify protected files (`server.ts`, middleware, build config) — flag for code owner
