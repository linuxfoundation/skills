<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# FGA-Protected Resource Types in LFX V2

All access control for LFX V2 resources is enforced through OpenFGA (Fine-Grained
Authorization). Resource services publish FGA sync messages to `lfx.fga-sync.*` NATS
subjects, which are consumed by `lfx-v2-fga-sync`.

**How to find all types**: check each backend service's `docs/fga-contract.md` for the
object types it manages, the NATS subjects it publishes to, and the payload shape for
each operation.

The full catalog of services and their object types is also maintained in
[lfx-v2-fga-sync/docs/fga-catalog.md](https://github.com/linuxfoundation/lfx-v2-fga-sync/blob/main/docs/fga-catalog.md).

---

## FGA Object Types by Domain

Services that have a `docs/fga-contract.md` provide the full message schema, operations,
relations, and trigger conditions for their object types. Use it as the authoritative
reference when writing or reviewing access control code for that service.

### Projects — `lfx-v2-project-service`

FGA contract: [docs/fga-contract.md](https://github.com/linuxfoundation/lfx-v2-project-service/blob/main/docs/fga-contract.md)

| Object type | Operations |
|-------------|------------|
| `project` | `update_access`, `delete_access` |

### Committees — `lfx-v2-committee-service`

FGA contract: [docs/fga-contract.md](https://github.com/linuxfoundation/lfx-v2-committee-service/blob/main/docs/fga-contract.md)

| Object type | Operations |
|-------------|------------|
| `committee` | `update_access`, `delete_access`, `member_put`, `member_remove` |

### Meetings — `lfx-v2-meeting-service`

FGA contract: [docs/fga-contract.md](https://github.com/linuxfoundation/lfx-v2-meeting-service/blob/main/docs/fga-contract.md)

| Object type | Operations |
|-------------|------------|
| `v1_meeting` | `update_access`, `delete_access`, `member_put`, `member_remove` |
| `v1_past_meeting` | `update_access`, `delete_access`, `member_put`, `member_remove` |

### Voting — `lfx-v2-voting-service`

FGA contract: [docs/fga-contract.md](https://github.com/linuxfoundation/lfx-v2-voting-service/blob/main/docs/fga-contract.md)

| Object type | Operations |
|-------------|------------|
| `vote` | `update_access`, `delete_access` |
| `vote_response` | `update_access`, `delete_access` |

### Surveys — `lfx-v2-survey-service`

FGA contract: [docs/fga-contract.md](https://github.com/linuxfoundation/lfx-v2-survey-service/blob/main/docs/fga-contract.md)

| Object type | Operations |
|-------------|------------|
| `survey` | `update_access`, `delete_access` |
| `survey_response` | `update_access`, `delete_access` |

### Mailing Lists — `lfx-v2-mailing-list-service`

FGA contract: [docs/fga-contract.md](https://github.com/linuxfoundation/lfx-v2-mailing-list-service/blob/main/docs/fga-contract.md)

| Object type | Operations |
|-------------|------------|
| `groupsio_service` | `update_access`, `delete_access` |
| `groupsio_mailing_list` | `update_access`, `delete_access`, `member_put`, `member_remove` |

---

## NATS Subjects

All services publish to these generic subjects consumed by `lfx-v2-fga-sync`:

| Subject | Purpose |
|---------|---------|
| `lfx.fga-sync.update_access` | Sync all relations for a resource |
| `lfx.fga-sync.delete_access` | Remove all relations when a resource is deleted |
| `lfx.fga-sync.member_put` | Add or update a per-user relation on a resource |
| `lfx.fga-sync.member_remove` | Remove a per-user relation from a resource |

For message format details and Go client code, see
`lfx-backend-builder/references/fga-patterns.md`.
