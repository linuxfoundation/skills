<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# OpenFGA & Access Control Patterns

The platform uses ReBAC (Relationship-Based Access Control) via OpenFGA. Permissions are
stored as tuples and checked at query time by the query-service via fga-sync.

## Tuple Format

```text
{user_type}:{user_id}#{relation}@{object_type}:{object_id}
```

Examples:

- `user:alice#writer@project:proj-123` — alice is a writer on this project
- `user:*#viewer@project:proj-123` — anyone (public) can view this project
- `project:parent-123#parent@project:child-456` — parent–child hierarchy link
- `user:bob#member@committee:abc` — bob is a member of this committee

## Access Message Format (create/update)

Publish to `lfx.update_access.{resource_type}`:

```json
{
  "uid": "resource-uuid",
  "object_type": "committee",
  "public": false,
  "relations": {
    "writer": ["user:alice"],
    "auditor": ["user:bob"]
  },
  "references": {
    "project": "parent-project-uuid"
  }
}
```

The `references.project` field is how fga-sync establishes the parent link in OpenFGA.
It writes a tuple like `project:{uid}#project@committee:{uid}`, enabling permission
inheritance from the parent project.

## Access Message Format (delete)

Publish to `lfx.delete_all_access.{resource_type}` with the plain UID as the message body
(not JSON — just the string):

```text
"abc-123-uuid"
```

fga-sync will purge all OpenFGA tuples for that object.

## Permission Inheritance

The OpenFGA model defines cascading relations. Permissions flow down the hierarchy:

```text
type project
  relations
    define parent: [project]
    define writer: [user] or writer from parent
    define auditor: [user] or writer or auditor from parent
    define viewer: [user:*] or auditor or auditor from parent

type committee
  relations
    define project: [project]
    define writer: writer from project
    define auditor: auditor from project
    define viewer: [user:*] or auditor from project
```

This means:

- A `writer` on a parent project is automatically a `writer` on all child projects
- A `writer` on a project is automatically a `writer` on all its committees
- Public resources use `user:*` (wildcard) — the query-service bypasses the FGA check entirely

## How the Query Service Uses FGA

For authenticated users, query-service:

1. Queries OpenSearch for matching resources
2. Reads `access_check_object` and `access_check_relation` from each document
3. Sends a batch check request to fga-sync: `{object}#{relation}@user:{principal}`
4. Drops any resource where fga-sync returns `false`

**If `access_check_object` or `access_check_relation` is empty in the OpenSearch document,
the resource is silently dropped from results** — a common debugging gotcha.

For anonymous users, query-service skips FGA entirely and filters OpenSearch by `public: true`.

## fga-sync Cache

fga-sync caches access check results in a NATS JetStream KV bucket (`fga-sync-cache`).
Cache invalidation uses a single `inv` timestamp key — every successful OpenFGA write bumps
it, making all older cached entries stale.

If you suspect stale cache results, look for `"cache invalidation failed"` in fga-sync logs.

## Publishing Access Messages — Generic vs Custom Handler

fga-sync has **generic handlers** that work with any resource type. You do **not** need
to add a new handler in fga-sync for a new resource type. Publish to the generic subjects:

| Subject | Purpose |
| --- | --- |
| `lfx.fga-sync.update_access` | Create/update access tuples for a resource |
| `lfx.fga-sync.delete_access` | Delete all tuples for a resource (on delete) |
| `lfx.fga-sync.member_put` | Add a user to a resource with one or more relations |
| `lfx.fga-sync.member_remove` | Remove specific or all relations for a user |

All use the `GenericFGAMessage` envelope:

```go
type GenericFGAMessage struct {
    ObjectType string      `json:"object_type"` // e.g. "committee"
    Operation  string      `json:"operation"`   // matches subject suffix: "update_access", "member_put", etc.
    Data       interface{} `json:"data"`
}
```

### update_access (create/update)

```go
msg := GenericFGAMessage{
    ObjectType: "sponsorship",
    Operation:  "update_access",
    Data: map[string]interface{}{
        "uid":    resource.UID,
        "public": resource.Public,
        "relations": map[string][]string{
            "writer": {"alice"},
        },
        "references": map[string][]string{
            "project": {resource.ProjectUID},
        },
        // "exclude_relations": ["participant"] — omit relations managed separately
    },
}
nc.Publish("lfx.fga-sync.update_access", payload)
```

`references` values can be just the UID (handler prepends `{type}:`) or the full
`type:uid` string — both are accepted.

### delete_access (on resource delete)

```go
msg := GenericFGAMessage{
    ObjectType: "sponsorship",
    Operation:  "delete_access",
    Data: map[string]interface{}{"uid": uid},
}
nc.Publish("lfx.fga-sync.delete_access", payload)
```

### member_put / member_remove

Used when managing individual user relations (e.g. adding/removing a committee member):

```go
// Add member
GenericFGAMessage{ObjectType: "committee", Operation: "member_put",
    Data: map[string]interface{}{
        "uid": committeeUID, "username": "alice", "relations": []string{"member"},
    }}

// Remove member (empty relations = remove all)
GenericFGAMessage{ObjectType: "committee", Operation: "member_remove",
    Data: map[string]interface{}{
        "uid": committeeUID, "username": "alice", "relations": []string{},
    }}
```

`member_put` is idempotent and supports `mutually_exclusive_with` for role transitions.
See `lfx-v2-fga-sync/docs/client-guide.md` for the full reference.

### Custom handlers

Only add a resource-specific handler in fga-sync (e.g. `handler_sponsorship.go`) if the
generic message format cannot express the required logic. Prefer the generic subjects.

### OpenFGA authorization model

When adding a new FGA type, update the authorization model in
`lfx-v2-helm/charts/lfx-platform/templates/openfga/model.yaml`:

```text
type sponsorship
  relations
    define project: [project]
    define viewer: viewer from project
    define writer: writer from project
    define auditor: auditor from project
```

Also update the Heimdall ruleset in the service's Helm chart to add `openfga_check` rules
per HTTP verb/path.

## Debugging Access Issues

When a user can't see a resource they should have access to, there are two root causes:

### 1. Indexing problem — document missing or stale in OpenSearch

Query OpenSearch directly:

```bash
curl "$OPENSEARCH_URL/lfx-resources/_search" -H 'Content-Type: application/json' -d '{
  "query": {"bool": {"must": [
    {"term": {"object_type": "committee"}},
    {"term": {"object_id": "<uid>"}},
    {"term": {"latest": true}}
  ]}},
  "_source": ["access_check_object", "access_check_relation", "public"]
}'
```

- No results → index message was never published or indexer failed to process it
- Results but `access_check_object` empty → `IndexingConfig` was missing or malformed
- Fix: trigger a no-op update on the resource to republish both NATS messages

### 2. Permissions problem — FGA tuple missing or wrong

Check existing tuples:

```bash
fga tuple read --object committee:<uid>
```

Common causes:

- `update_access` NATS message never published (check resource service logs for publish errors)
- Wrong `references` in the access message (wrong parent project UID)
- User's LFID in the JWT doesn't match the username stored in the tuple
- Member was added without a `username` — fga-sync skips tuple writes silently when username is empty
- Cache is stale — any successful OpenFGA write re-invalidates; or manually write to the `inv` KV key

## FGA Contract — Per-Service Documentation

Services that follow the FGA contract pattern keep a `docs/fga-contract.md` at the root
of their repo. This is the authoritative reference for that service's object types,
message schemas, operations, relations, and trigger conditions — derived directly from
the source code.

**Read this before writing or modifying FGA message construction for an existing service.**
It tells you what subjects are used, what payload shape is expected, and what conditions
cause messages to be skipped (e.g. empty username).

**Update it in the same PR as any FGA messaging change.** The doc must stay in sync with
the code.

The [committee-service](https://github.com/linuxfoundation/lfx-v2-committee-service/blob/main/docs/fga-contract.md)
is the reference implementation of this pattern. Use it as a template when adding a
contract to a new service.

For a full index of all services and their FGA object types, see
`lfx-coordinator/references/fga-protected-types.md`.
