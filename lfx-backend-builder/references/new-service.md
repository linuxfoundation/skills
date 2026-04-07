<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Building a New Resource Service

Before starting, determine your service type — see [service-types.md](service-types.md).
Then clone the appropriate template repo and follow the steps below.

## 1. Copy the Template

| Type | Template repo |
| --- | --- |
| Native (owns data) | `lfx-v2-committee-service` |
| Wrapper (proxies external system) | `lfx-v2-voting-service` |

Do a global find-and-replace on the resource name (e.g. `committee` → `sponsorship`,
`Committee` → `Sponsorship`).

## 2. Define the Domain Model

In `internal/domain/model/`, create the domain struct:

```go
type Sponsorship struct {
    UID        string
    ProjectUID string
    Name       string
    Public     bool
}

// Tags returns values used for exact-match filtering in OpenSearch.
func (s Sponsorship) Tags() []string {
    return []string{
        fmt.Sprintf("project_uid:%s", s.ProjectUID),
    }
}
```

The `Tags()` method is called when building the `IndexingConfig` — see step 5.

## 3. Define the API with Goa

In `cmd/{service}/design/`, define the resource and its endpoints using the Goa DSL.
Then regenerate:

```bash
make apigen
```

Never edit files in `gen/` — they are overwritten on every `make apigen` run.

## 4. Wire the Handler and Service

Connect the Goa-generated API handler to your domain service layer:

```text
Handler (gen/) → converts payload → Service (internal/service/) → Storage / Proxy client
```

Conversion functions (`payloadToDomain`, `domainToResponse`) live in the handler
package alongside the API implementation.

## 5. Publish NATS Messages on Writes

In `internal/infrastructure/nats/messaging_publish.go`, construct the index message
using `IndexingConfig`:

```go
public := resource.Public
indexingConfig := &indexerTypes.IndexingConfig{
    ObjectID:             resource.UID,
    AccessCheckObject:    fmt.Sprintf("sponsorship:%s", resource.UID),
    AccessCheckRelation:  "viewer",
    HistoryCheckObject:   fmt.Sprintf("sponsorship:%s", resource.UID),
    HistoryCheckRelation: "auditor",
    SortName:             resource.Name,
    NameAndAliases:       []string{resource.Name},
    ParentRefs:           []string{fmt.Sprintf("project:%s", resource.ProjectUID)},
    Tags:                 resource.Tags(),
    Public:               &public,
}

msg := indexerTypes.IndexerMessageEnvelope{
    Action:         constants.ActionCreated,
    Headers:        headersFromContext(ctx),
    Data:           resource,
    IndexingConfig: indexingConfig,
}
```

If the resource type has its own OpenFGA type, also publish an access message to
`lfx.fga-sync.update_access` using the `GenericFGAMessage` format. See
[fga-patterns.md](fga-patterns.md) for the payload shape.

Both messages are published concurrently — see `committee_writer.go` in
`lfx-v2-committee-service` for the pattern.

## 6. Add the OpenFGA Type (if needed)

If the resource needs its own FGA type, update the authorization model in
`lfx-v2-helm/charts/lfx-platform/templates/openfga/model.yaml`:

```text
type sponsorship
  relations
    define project: [project]
    define viewer: viewer from project
    define writer: writer from project
    define auditor: auditor from project
```

You do **not** need to add a handler in `lfx-v2-fga-sync` — the generic handlers
on `lfx.fga-sync.*` subjects handle any object type automatically. Only add a
resource-specific handler if the generic format cannot express the required logic.

## 7. Add Heimdall Auth Rules

In the service's Helm chart (`charts/{service}/`), add `openfga_check` rules for
each HTTP verb and path that requires authorization. Reference an existing service's
chart for the pattern.

## 8. Health Endpoints

Both `/livez` and `/readyz` must be implemented:

- `/livez` — always returns 200; no dependency checks
- `/readyz` — checks NATS connection (and any other critical deps); returns 503 if unhealthy

## 9. OpenTelemetry

New services must include the full OTEL stack:

- Tracing (spans around NATS calls, storage operations, external HTTP calls)
- Metrics (request counts, latencies)
- Structured logging via `slog` + `slog-otel` for log/trace correlation

## Checklist

- [ ] Domain model with `Tags()` method
- [ ] Goa design + `make apigen` run
- [ ] Handler ↔ service ↔ storage wired
- [ ] Index message published on every write (create, update, delete)
- [ ] Access message published on every write (if resource has FGA type)
- [ ] `docs/fga-contract.md` added (if resource has FGA type)
- [ ] OpenFGA authorization model updated (if resource has FGA type)
- [ ] Heimdall auth rules in Helm chart
- [ ] `/livez` and `/readyz` endpoints
- [ ] Full OTEL stack (tracing, metrics, logs)
- [ ] Queue group subscriptions for all NATS handlers
- [ ] 25-second graceful shutdown with NATS drain
