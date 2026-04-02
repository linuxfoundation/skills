<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Indexer Service Patterns

The indexer-service subscribes to `lfx.index.*` NATS subjects and writes documents into
OpenSearch. It is designed to be fully generic — resource services tell it everything it
needs via the message payload.

## Message Subject

Publish to `lfx.index.{resource_type}`:

```text
lfx.index.committee
lfx.index.committee_member
lfx.index.vote
lfx.index.survey
```

## IndexerMessageEnvelope

The payload published to the indexer subject:

```go
type IndexerMessageEnvelope struct {
    Action         constants.MessageAction `json:"action"`           // "created", "updated", "deleted"
    Headers        map[string]string       `json:"headers"`          // auth headers from request context
    Data           any                     `json:"data"`             // full resource struct; bare UID string for deletes
    Tags           []string                `json:"tags,omitempty"`
    IndexingConfig *IndexingConfig         `json:"indexing_config,omitempty"`
}
```

- `Headers` carries `Authorization` and `X-On-Behalf-Of` from the request context —
  these become the audit principal in the OpenSearch document
- `Data` is stored as-is in the `data` field of the OpenSearch document (schema-free `flat_object`)
- For deletes: set `action = "deleted"` and `data` = the plain UID string

Always use action constants — never hardcode strings:

```go
constants.ActionCreated  // "created"
constants.ActionUpdated  // "updated"
constants.ActionDeleted  // "deleted"
```

## IndexingConfig — the Current Pattern

`IndexingConfig` is how a resource service provides all the metadata the indexer needs to
build a well-structured OpenSearch document. **All new services must include it.**

Without `IndexingConfig`, the indexer falls back to resource-specific "enrichers" — that
is the old, deprecated pattern still used by `project-service`. Do not follow it.

```go
type IndexingConfig struct {
    // Required — identifies the resource and how to check access
    ObjectID             string `json:"object_id"`              // resource UUID
    AccessCheckObject    string `json:"access_check_object"`    // e.g. "vote:abc-123"
    AccessCheckRelation  string `json:"access_check_relation"`  // e.g. "viewer"
    HistoryCheckObject   string `json:"history_check_object"`   // e.g. "vote:abc-123"
    HistoryCheckRelation string `json:"history_check_relation"` // e.g. "auditor"

    // Search and discovery fields
    Public         *bool         `json:"public,omitempty"`           // true = skip auth check for anonymous
    SortName       string        `json:"sort_name,omitempty"`        // sortable name
    NameAndAliases []string      `json:"name_and_aliases,omitempty"` // typeahead / search-as-you-type
    ParentRefs     []string      `json:"parent_refs,omitempty"`      // e.g. ["project:xyz", "committee:abc"]
    Tags           []string      `json:"tags,omitempty"`             // exact-match filtering
    Fulltext       string        `json:"fulltext,omitempty"`         // free-text search blob
    Contacts       []ContactBody `json:"contacts,omitempty"`
}
```

### Choosing search fields

| Field | When to populate |
|---|---|
| `NameAndAliases` | Primary name/title users search for (typeahead) |
| `Tags` | Values used for exact filtering (e.g. `project_uid:abc`, `status:active`) |
| `Fulltext` | Any text content users might search within |
| `ParentRefs` | Parent resource refs — always include if the resource belongs to a project |
| `data` only | Fields that are display-only and never searched |

### Full example (voting-service pattern)

```go
public := vote.Public
indexingConfig := &indexerTypes.IndexingConfig{
    ObjectID:             vote.UID,
    AccessCheckObject:    fmt.Sprintf("vote:%s", vote.UID),
    AccessCheckRelation:  "viewer",
    HistoryCheckObject:   fmt.Sprintf("vote:%s", vote.UID),
    HistoryCheckRelation: "auditor",
    SortName:             vote.Name,
    NameAndAliases:       []string{vote.Name},
    ParentRefs:           []string{fmt.Sprintf("project:%s", vote.ProjectUID)},
    Tags:                 vote.Tags(), // from domain model Tags() method
    Fulltext:             fmt.Sprintf("%s %s", vote.Name, vote.Description),
    Public:               &public,
}

msg := indexerTypes.IndexerMessageEnvelope{
    Action:         constants.ActionCreated,
    Headers:        headersFromContext(ctx),
    Data:           vote,
    IndexingConfig: indexingConfig,
}
```

## What the Indexer Does With the Message

1. Parses the `IndexerMessageEnvelope` from the NATS payload
2. If `IndexingConfig` is present: builds the OpenSearch document directly from it (generic path)
3. If `IndexingConfig` is absent: looks up a resource-specific enricher by object type (deprecated path)
4. Inserts a new document with `latest: true`
5. A background janitor later sets `latest: false` on old versions

The indexer **never updates** documents in place — every change creates a new version. This
gives a full audit history at no extra cost.

## OpenSearch Document Structure

Key fields in every indexed document:

| Field | Populated from | Purpose |
|---|---|---|
| `object_ref` | `{type}:{id}` | Primary identifier (e.g. `committee:abc-123`) |
| `object_type` | NATS subject suffix | Filtering queries by resource type |
| `object_id` | `IndexingConfig.ObjectID` | UUID lookup |
| `parent_refs` | `IndexingConfig.ParentRefs` | Hierarchy navigation |
| `sort_name` | `IndexingConfig.SortName` | Sorting results |
| `name_and_aliases` | `IndexingConfig.NameAndAliases` | Typeahead search field |
| `public` | `IndexingConfig.Public` | Anonymous queries filter on this; skips FGA check |
| `access_check_query` | `{AccessCheckObject}#{AccessCheckRelation}` | Used by query-service to build FGA check |
| `latest` | Set by indexer | `true` for current version only |
| `data` | `IndexerMessageEnvelope.Data` | Full resource data (schema-free `flat_object`) |

## Adding a New Field to an Existing Resource

Adding a new field to the `data` payload requires no OpenSearch schema changes — `data` is
a `flat_object` and OpenSearch handles new keys dynamically.

If the new field should also be **searchable**, update the `IndexingConfig` construction in
the resource service's NATS publisher to include it in the appropriate search field
(`NameAndAliases`, `Tags`, or `Fulltext`).

## Indexer Contract — Per-Service Documentation

Services that follow the indexer contract pattern keep a `docs/indexer-contract.md` at the
root of their repo. This is the authoritative reference for that service's data schemas,
tags, access control config, parent references, and fulltext fields — derived directly from
the source code.

**Read this before writing or modifying indexing code for an existing service.** It tells
you what is already indexed and how, so you don't duplicate tags, miss required fields, or
break existing query patterns.

**Update it in the same PR as any indexing change.** The doc must stay in sync with the
code.

The [committee-service](https://github.com/linuxfoundation/lfx-v2-committee-service/blob/main/docs/indexer-contract.md)
is the reference implementation of this pattern. Use it as a template when adding a
contract to a new service.
