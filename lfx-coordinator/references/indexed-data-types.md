<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Queryable Resource Types in LFX V2

All resource types are queryable via the query service (`lfx-v2-query-service`) using
`GET /query/resources?v=1&type=<type>`. The query service subscribes to a shared
OpenSearch index populated by `lfx-v2-indexer-service`, which itself subscribes to all
`lfx.index.*` NATS subjects using a wildcard (`lfx.index.>`).

**How to find all types**: check each backend service's `pkg/constants/subjects.go` (or
equivalent) for constants of the form `"lfx.index.<type>"`. Do NOT rely solely on the
indexer service's `ObjectType*` constants — they lag behind active publishers.

---

## Resource Types by Domain

Services that have a `docs/indexer-contract.md` provide the full data schema, tags, access control config, parent references, and fulltext/search-field definitions for their resource types. Use it as the authoritative reference when writing queries or indexing code for that service.

### Projects — `lfx-v2-project-service`

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-project-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `project` | `lfx.index.project` | `pkg/constants/nats.go` |
| `project_settings` | `lfx.index.project_settings` | `pkg/constants/nats.go` |

### Committees — `lfx-v2-committee-service`

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-committee-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `committee` | `lfx.index.committee` | `pkg/constants/subjects.go` |
| `committee_settings` | `lfx.index.committee_settings` | `pkg/constants/subjects.go` |
| `committee_member` | `lfx.index.committee_member` | `pkg/constants/subjects.go` |
| `committee_invite` | `lfx.index.committee_invite` | `pkg/constants/subjects.go` |
| `committee_application` | `lfx.index.committee_application` | `pkg/constants/subjects.go` |

### Meetings — `lfx-v2-meeting-service`

> The `v1_` prefix reflects that the data originates from the v1 Zoom/ITX API.

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-meeting-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `v1_meeting` | `lfx.index.v1_meeting` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_meeting_registrant` | `lfx.index.v1_meeting_registrant` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_meeting_rsvp` | `lfx.index.v1_meeting_rsvp` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_meeting_attachment` | `lfx.index.v1_meeting_attachment` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_past_meeting` | `lfx.index.v1_past_meeting` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_past_meeting_participant` | `lfx.index.v1_past_meeting_participant` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_past_meeting_attachment` | `lfx.index.v1_past_meeting_attachment` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_past_meeting_recording` | `lfx.index.v1_past_meeting_recording` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_past_meeting_transcript` | `lfx.index.v1_past_meeting_transcript` | `internal/infrastructure/eventing/nats_publisher.go` |
| `v1_past_meeting_summary` | `lfx.index.v1_past_meeting_summary` | `internal/infrastructure/eventing/nats_publisher.go` |

### Mailing Lists — `lfx-v2-mailing-list-service`

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-mailing-list-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `groupsio_service` | `lfx.index.groupsio_service` | `pkg/constants/subjects.go` |
| `groupsio_service_settings` | `lfx.index.groupsio_service_settings` | `pkg/constants/subjects.go` |
| `groupsio_mailing_list` | `lfx.index.groupsio_mailing_list` | `pkg/constants/subjects.go` |
| `groupsio_mailing_list_settings` | `lfx.index.groupsio_mailing_list_settings` | `pkg/constants/subjects.go` |
| `groupsio_member` | `lfx.index.groupsio_member` | `pkg/constants/subjects.go` |
| `groupsio_artifact` | `lfx.index.groupsio_artifact` | `pkg/constants/subjects.go` |

### Voting — `lfx-v2-voting-service`

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-voting-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `vote` | `lfx.index.vote` | `internal/infrastructure/eventing/nats_publisher.go` |
| `vote_response` | `lfx.index.vote_response` | `internal/infrastructure/eventing/nats_publisher.go` |

### Surveys — `lfx-v2-survey-service`

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-survey-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `survey` | `lfx.index.survey` | `internal/infrastructure/eventing/nats_publisher.go` |
| `survey_response` | `lfx.index.survey_response` | `internal/infrastructure/eventing/nats_publisher.go` |
| `survey_template` | `lfx.index.survey_template` | `internal/infrastructure/eventing/nats_publisher.go` |

### Members — `lfx-v2-member-service`

> **Note:** The indexer publisher uses placeholder types pending a future implementation ticket. The types and subjects below reflect the intended contract.

Indexer contract: [docs/indexer-contract.md](https://github.com/linuxfoundation/lfx-v2-member-service/blob/main/docs/indexer-contract.md)

| `type` | NATS subject | Source file |
|--------|-------------|-------------|
| `membership_tier` | `lfx.index.membership_tier` | `internal/domain/port/event_publisher.go` |
| `project_membership` | `lfx.index.project_membership` | `internal/domain/port/event_publisher.go` |
| `key_contact` | `lfx.index.key_contact` | `internal/domain/port/event_publisher.go` |
| `b2b_org` | `lfx.index.b2b_org` | `internal/domain/port/event_publisher.go` |

---

## Implications for the `lfx-backend-builder`

When adding indexing for a **new field** on an existing type, the change goes in the
service that owns that type's NATS publish (see Source file column above). The pattern
is always the same — update the `IndexingConfig` passed to `sendIndexerMessage`:

- `name_and_aliases` — controls typeahead search
- `tags` — controls tag filtering
- `parent_refs` — controls parent navigation
- `data` — the full resource snapshot returned in query results (include any new fields here)

When adding a **new resource type**, the publishing service needs a new
`lfx.index.<new_type>` subject constant and a corresponding `sendIndexerMessage` call.
The indexer picks it up automatically via its wildcard subscription — no indexer changes
needed.

For query service usage details (API parameters, access control, CEL filters), see
`lfx-backend-builder/references/query-service.md`.
