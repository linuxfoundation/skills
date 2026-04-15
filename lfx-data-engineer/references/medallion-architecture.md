<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Medallion Architecture Guide

The lf-dbt project follows a four-layer medallion architecture. Each layer has
a specific purpose, materialization strategy, and set of conventions.

## Layer Overview

```text
┌──────────────────────────────────────────────────────────────────┐
│  Platinum   │  Pre-computed reports with time windows            │
│             │  Dashboard-ready data (PCC, ID, OD, Insights)      │
├─────────────┼────────────────────────────────────────────────────┤
│  Gold       │  Aggregated metrics for specific business cases    │
│             │  Code contributions by org, enrollment counts      │
├─────────────┼────────────────────────────────────────────────────┤
│  Silver     │  Business logic, joins, transformations            │
│             │  Reusable objects: Users, Projects, Activities     │
├─────────────┼────────────────────────────────────────────────────┤
│  Bronze     │  1:1 with source data                              │
│             │  Column renames, type casting, delete filtering    │
└─────────────┴────────────────────────────────────────────────────┘
         ▲              ▲              ▲              ▲
     Raw Sources    source()        ref()          ref()
```

---

## Bronze Layer

### Purpose

Bronze models provide a clean, renamed view of raw source data. They are the
only layer that reads from `source()` — all other layers use `ref()`.

### Conventions

- **Materialization:** `view` (default)
- **Schema:** `bronze_*` per source system (e.g., `bronze_fivetran_platform`)
- **One model per source table** — no joins
- **No business logic** — only column renames, type casting, and filtering

### What Belongs Here

- Column renames from source naming to snake_case business names
- Type casting (e.g., string to date)
- Filtering deleted records (`_fivetran_deleted`)
- Filtering test data (`is_test`)
- Timestamp normalization to UTC using `format_timestamp()`

### Example: Bronze Event Model

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

{% set warehouse = get_warehouse('hourly') %}

{{ config(snowflake_warehouse=warehouse) }}

SELECT
    id AS event_id,
    event_start_date,
    event_end_date,
    event_title AS event_name,
    currency,
    project_id,
    salesforce_id AS salesforce_event_id,
    event_location,
    IFF(event_status_name = 'Complete', 'Completed', event_status_name) AS event_status,
    city AS event_city,
    country AS event_country,
    created_date AS event_created_ts,
    event_category,
    event_code,
    account_stub AS event_account_stub,
    source,
    lastmodified_date AS updated_at

FROM {{ source('fivetran_platform', 'event') }}
WHERE
    NOT _fivetran_deleted
    AND NOT is_test
```

### Key Patterns

- `source('schema_name', 'table_name')` or `smart_source()` for dev lookback
- `get_warehouse('hourly')` for large source tables
- Column naming: `_ts` for timestamps, `_date` for dates, `is_`/`has_` for booleans
- Filter `_fivetran_deleted` when the source has Fivetran soft deletes

### File Naming

`bronze_{source_system}_{table_name}.sql`

Examples:
- `bronze_fivetran_platform_events.sql`
- `bronze_fivetran_salesforce_projects.sql`
- `bronze_kafka_crowd_dev_activities.sql`

---

## Silver Layer

### Purpose

Silver models apply business logic, join multiple bronze models, and create
reusable business objects. They are divided into two subfolders:

- **`dim/`** — Dimensions: slowly-changing attributes (users, projects, organizations)
- **`fact/`** — Facts: events and transactions (activities, registrations, contributions)

### Conventions

- **Materialization:** `table`
- **Schema:** `silver_dim` or `silver_fact`
- **Table naming:** The `generate_alias_name` macro strips the schema prefix.
  A model named `silver_dim_users.sql` becomes table `USERS` in the
  `SILVER_DIM` schema (not `SILVER_DIM_USERS`).
- **Block comment** at the top explaining purpose, questions answered, and data sources

### What Belongs Here

- Joins across multiple bronze models
- Business rules and transformations
- Deduplication logic
- Enrichment from reference data
- Reusable objects that serve multiple downstream use cases

### Example: Silver Dimension Model

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

/*
This model creates a standardized dimension table for projects.

## Purpose:
- Provides a comprehensive view of projects with all relevant attributes

## Questions this model can help answer:
1. What is the hierarchical structure of projects?
2. Which projects belong to specific foundations?
3. What is the current health score of a project?

## Data sources:
- bronze_fivetran_salesforce_projects
- silver_fact_crowd_dev_project_health_metrics
*/

{% set warehouse = get_warehouse('hourly') %}

{{ config(snowflake_warehouse=warehouse) }}

WITH latest_health_metrics AS (
    SELECT
        project_slug,
        metric_date AS health_metric_date,
        health_score,
        health_score_category
    FROM {{ ref('silver_fact_crowd_dev_project_health_metrics') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY project_slug
        ORDER BY metric_date DESC
    ) = 1
),

projects AS (
    SELECT
        project_id,
        project_name,
        project_slug,
        project_status
    FROM {{ ref('bronze_fivetran_salesforce_projects') }}
)

SELECT
    p.project_id,
    p.project_name,
    p.project_slug,
    p.project_status,
    h.health_score,
    h.health_score_category,
    h.health_metric_date
FROM projects p
LEFT JOIN latest_health_metrics h
    ON p.project_slug = h.project_slug
```

### Helper Models

Silver includes `helper_models/` subfolders for reusable SQL fragments. These
files start with a `_` prefix (e.g., `_silver_dim_project_spine.sql`) and are
not full models — they serve as building blocks for other models.

The `_silver_dim_project_spine.sql` helper is particularly important: it fans
out projects to their parent hierarchy for downstream aggregation.

### File Naming

- Dimensions: `silver_dim_{entity}.sql` (e.g., `silver_dim_users.sql`)
- Facts: `silver_fact_{domain}_{entity}.sql` (e.g., `silver_fact_event_registrations.sql`)
- Helpers: `_silver_{dim|fact}_{name}.sql` (e.g., `_silver_dim_project_spine.sql`)

---

## Gold Layer

### Purpose

Gold models combine silver models into purpose-built datasets for specific
business use cases. They answer specific analytical questions without requiring
additional joins.

### Conventions

- **Materialization:** `table`
- **Schema:** `gold_*` per domain (e.g., `gold_fact`, `gold_reporting`)
- **Surrogate keys** via `dbt_utils.generate_surrogate_key()` for composite primary keys
- **`unique_key`** in config for incremental models

### What Belongs Here

- Aggregated metrics (code contributions by org, enrollment counts)
- Purpose-built datasets that downstream consumers query directly
- Fan-out logic using the project spine helper

### Example: Gold Fact Model

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

{{ config(unique_key=["_key", "project_id"]) }}

SELECT
    ({{ dbt_utils.generate_surrogate_key(["c._key", "p.mapped_project_id"]) }}) AS activity_project_id,
    c._key,
    c.activity_id,
    c.activity_ts,
    c.activity_type,
    c.activity_category,
    c.member_id,
    c.github_username,
    c.repository_url,
    p.mapped_project_id AS project_id,
    p.mapped_project_slug AS project_slug,
    p.mapped_project_name AS project_name,
    c.additions,
    c.deletions,
    COALESCE(c.is_pr_approved, FALSE) AS is_pr_approved,
    c.is_org_contribution,
    c.member_is_bot,
    (
        ROW_NUMBER() OVER (
            PARTITION BY p.mapped_project_id, c.member_id
            ORDER BY c.activity_ts
        ) = 1
    ) AS is_members_first_project_contribution

FROM {{ ref("silver_fact_crowd_dev_activities") }} c
LEFT JOIN {{ ref("_silver_dim_project_spine") }} p
    ON c.project_id = p.base_project_id
WHERE
    p.mapped_project_id IS NOT NULL
    AND {{ filter_code_contributions_non_bot('c') }}
```

### File Naming

`gold_fact_{domain}.sql` or `gold_{purpose}_{entity}.sql`

Examples:
- `gold_fact_code_contributions.sql`
- `gold_fact_enrollments.sql`
- `gold_fact_course_purchases.sql`

---

## Platinum Layer

### Purpose

Platinum models produce dashboard-ready data with pre-computed time windows.
Consumers query platinum tables directly without needing date range filters.

### Conventions

- **Materialization:** `table`
- **Schema:** `platinum*` per product (e.g., `platinum_organization_dashboard`)
- **Date range macros** for time-windowed aggregations
- **`get_warehouse()`** for resource-intensive computations
- **`GROUP BY ALL`** is acceptable for complex aggregations
- **`QUALIFY`** with `ROW_NUMBER()` for deduplication

### What Belongs Here

- Pre-computed metrics by time period (last 7 days, last 30 days, YTD)
- Period-over-period comparisons (current vs previous period)
- Dashboard-specific data shapes
- Delta calculations using `add_delta_columns()`

### Example: Platinum Dashboard Model

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

{% set warehouse = get_warehouse('hourly') %}

{{ config(snowflake_warehouse=warehouse) }}

WITH sponsors AS (
    SELECT
        event_id,
        contact_id
    FROM {{ ref('silver_fact_event_sponsorships') }}
    GROUP BY ALL
),

event_registrations AS (
    SELECT
        er.registration_id,
        mu.user_id,
        mu.user_name,
        er.event_id,
        er.event_name,
        er.event_start_date,
        er.event_end_date,
        er.project_id,
        er.user_attended,
        er.registration_status,
        CASE
            WHEN sp.contact_id IS NOT NULL THEN 'Sponsor'
            WHEN er.is_event_speaker THEN 'Speaker'
            WHEN er.user_attended = TRUE THEN 'Attendee'
            ELSE 'Registered'
        END AS user_role
    FROM {{ ref('silver_fact_event_registrations') }} er
    INNER JOIN {{ ref('bronze_fivetran_salesforce_merged_user') }} mu
        ON er.user_id = mu.user_id
    LEFT JOIN sponsors sp
        ON mu.user_id = sp.contact_id
        AND er.event_id = sp.event_id
    WHERE
        er.event_name IS NOT NULL
        AND er.event_start_date IS NOT NULL
    GROUP BY ALL
)

SELECT
    ({{ dbt_utils.generate_surrogate_key(['user_id', 'event_id']) }}) AS _key,
    registration_id,
    user_id,
    user_name,
    event_id,
    event_name,
    event_start_date,
    event_end_date,
    project_id,
    user_attended,
    user_role,
    registration_status
FROM event_registrations
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_id, event_id
    ORDER BY event_start_date
) = 1
```

### Product Folders

Platinum models are organized by dashboard/product:

| Folder | Dashboard |
|--------|-----------|
| `individual_dashboard/` | Individual Dashboard (ID) |
| `organization_dashboard/` | Organization Dashboard (OD) |
| `lfx_one/` | LFX One platform |
| `events/` | Events metrics |
| `code_contributions/` | Code contribution analytics |
| `enrollments/` | Training enrollment reports |
| `membership/` | Membership metrics |
| `marketing/` | Marketing analytics |
| `sales_metrics/` | Sales pipeline reports |

### File Naming

`platinum_{product}_{entity}.sql`

Examples:
- `platinum_individual_dashboard_event_registrations.sql`
- `platinum_organization_dashboard_overview.sql`
- `platinum_lfx_one_project_code_commits.sql`

---

## Decision Tree: Which Layer?

```text
Is this reading directly from a raw source table?
  └─ YES → Bronze
  └─ NO  → Does it create a reusable business object (users, projects, activities)?
              └─ YES → Silver (dim/ for attributes, fact/ for events)
              └─ NO  → Does it aggregate metrics for a specific use case?
                          └─ YES → Is it pre-computed with time windows for a dashboard?
                                      └─ YES → Platinum
                                      └─ NO  → Gold
                          └─ NO  → Silver (it's probably a helper or intermediate model)
```

## Schema Mapping Reference

| Layer + Folder | Snowflake Schema (Production) |
|---------------|-------------------------------|
| `bronze/fivetran_platform/` | `BRONZE_FIVETRAN_PLATFORM` |
| `bronze/fivetran_salesforce/` | `BRONZE_SALESFORCE` |
| `bronze/kafka_crowd_dev/` | `BRONZE_KAFKA_CROWD_DEV` |
| `bronze/stripe/` | `BRONZE_STRIPE` |
| `silver/dim/` | `SILVER_DIM` |
| `silver/fact/` | `SILVER_FACT` |
| `gold/fact/` | `GOLD_FACT` |
| `gold/reporting/` | `GOLD_REPORTING` |
| `platinum/individual_dashboard/` | `PLATINUM_INDIVIDUAL_DASHBOARD` |
| `platinum/organization_dashboard/` | `PLATINUM_ORGANIZATION_DASHBOARD` |
| `platinum/lfx_one/` | `PLATINUM_LFX_ONE` |

In dev, schemas are prefixed with your personal schema:
`{your_schema}_BRONZE_FIVETRAN_PLATFORM`, etc.
