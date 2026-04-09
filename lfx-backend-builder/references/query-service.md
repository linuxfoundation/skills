<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Query Service Patterns

The query-service provides a generic HTTP search API over OpenSearch. It does not know
about individual resource types — it queries a shared `resources` index and delegates
access control to fga-sync. Indexer-service populates that index from NATS events
published by resource services.

## How the Three Services Connect

```text
Resource Service
    → publishes lfx.index.{type}       → indexer-service → OpenSearch (resources index)
    → publishes lfx.fga-sync.*         → fga-sync → OpenFGA

Client Request
    → GET /query/resources
        → query-service queries OpenSearch
        → for each non-public result: batch access check via NATS → fga-sync
        → drops resources where access is denied
        → returns filtered results
```

The `access_check_object` and `access_check_relation` fields written into each
OpenSearch document by the indexer (from the resource service's `IndexingConfig`) are
what the query-service uses to build the FGA check. If either field is empty, the
document is silently dropped from results.

## HTTP API

### GET /query/resources

| Parameter | Type | Description |
| --- | --- | --- |
| `v` | int (required) | API version, must be `1` |
| `name` | string | Typeahead/prefix search on `name_and_aliases` |
| `type` | string | Filter by `object_type` (e.g. `committee`) |
| `parent` | string | Filter by `parent_refs` (format: `project:uuid`) |
| `tags` | []string | OR filter — any tag matches |
| `tags_all` | []string | AND filter — all tags must match |
| `filters` | []string | AND filter — exact field filters (format: `field:value`, against `data.*`). Prefer `filters_all` going forward |
| `filters_all` | []string | AND filter — all provided filters must match. Explicit preferred alias for `filters` |
| `filters_or` | []string | OR filter — at least one provided filter must match (format: `field:value`, against `data.*`) |
| `date_field` | string | Field within `data` to range-filter on |
| `date_from` / `date_to` | string | ISO 8601 or `YYYY-MM-DD` |
| `cel_filter` | string | CEL expression for in-process filtering (applied after OpenSearch, before access check) |
| `sort` | string | `name_asc` (default), `name_desc`, `updated_asc`, `updated_desc` |
| `page_size` | int | 1–1000, default 50 |
| `page_token` | string | Opaque pagination token (keyset-based) |

**Response**:

```json
{
  "resources": [
    { "type": "committee", "id": "uuid", "data": { ... } }
  ],
  "page_token": "opaque-token-or-omitted",
  "cache_control": "public, max-age=300"
}
```

`data` is the full resource object as stored by the indexer — schema-free, no
migration needed for new fields.

### GET /query/resources/count

Same parameters as above (minus `cel_filter`, `sort`, pagination). Returns:

```json
{ "count": 42, "has_more": false }
```

## Anonymous vs Authenticated Requests

| | Anonymous (`_anonymous`) | Authenticated |
| --- | --- | --- |
| OpenSearch filter | `public: true` only | All documents |
| FGA check | Skipped | Batch check via NATS |
| Cache-Control | `public, max-age=300` | Not set |

Anonymous users are identified by the `_anonymous` principal (set when no valid JWT is
provided). They only see resources where `public: true` was set in the `IndexingConfig`.

## Access Control Flow

For authenticated requests, the query-service:

1. Runs the OpenSearch query — gets back all matching documents regardless of permissions
2. Builds a batch access check message — one line per non-public resource:

   ```text
   committee:abc-123#viewer@user:alice
   project:xyz-789#viewer@user:alice
   ```

   (format: `{access_check_object}#{access_check_relation}@user:{principal}`)
3. Sends to fga-sync via NATS request/reply:
   - Subject: `lfx.access_check.request`
   - Timeout: 15 seconds
4. Parses the tab-separated response:

   ```text
   committee:abc-123#viewer@user:alice\ttrue
   project:xyz-789#viewer@user:alice\tfalse
   ```

5. Drops any resource where the response is `false` or missing

The query-service deduplicates by `object_ref` so each FGA object is checked at most once
per request.

## OpenSearch Document Fields Used by Query Service

These fields must be correctly populated by the indexer (via `IndexingConfig`) for a
resource to be discoverable and accessible:

| Field | Purpose | If missing/wrong |
| --- | --- | --- |
| `object_type` | Type filtering (`type=` param) | Resource won't match type queries |
| `parent_refs` | Parent filtering (`parent=` param) | Resource won't appear in parent queries |
| `name_and_aliases` | Typeahead search (`name=` param) | Resource won't appear in name searches |
| `tags` | Tag filtering | Resource won't match tag queries |
| `public` | Skips FGA check for anonymous users | Anonymous users can't see it |
| `access_check_object` | Identifies FGA object to check | Resource silently dropped from results |
| `access_check_relation` | FGA relation to check (e.g. `viewer`) | Resource silently dropped from results |
| `sort_name` | Sorting by name | May sort incorrectly |
| `data` | Returned as-is in the response | Missing fields in response |
| `latest` | Always filtered to `true` | Old versions hidden (correct behavior) |

**The most common debugging gotcha**: if a user can't see a resource they should have
access to, check that `access_check_object` and `access_check_relation` are populated
in the OpenSearch document. Query OpenSearch directly:

```bash
curl "$OPENSEARCH_URL/lfx-resources/_search" -H 'Content-Type: application/json' -d '{
  "query": {"bool": {"must": [
    {"term": {"object_id": "<uid>"}},
    {"term": {"latest": true}}
  ]}},
  "_source": ["access_check_object", "access_check_relation", "public"]
}'
```

## tags vs filters vs cel_filter

| Mechanism | Use for | How it works |
| --- | --- | --- |
| `tags` / `tags_all` | Values in the `tags` field (exact match) | OpenSearch `term` query |
| `filters` / `filters_all` | AND logic — all filters must match; values inside `data` (format: `field:value`) | Individual `term` clauses in OpenSearch `must` |
| `filters_or` | OR logic — at least one filter must match; same format as `filters` | Nested `bool/should` with `minimum_should_match: 1` inside `must` |
| `cel_filter` | Complex expressions not expressible via tags/filters | Applied in-process after OpenSearch, before access check |

Resource services control what appears in `tags` via the `Tags()` method on their
domain model — see [indexer-patterns.md](indexer-patterns.md).
