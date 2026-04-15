---
name: lfx-data-engineer
description: >
  Guide non-dbt developers through building PR-ready data models, tests, and
  transformations in the lf-dbt repo. Encodes the medallion architecture
  (bronze/silver/gold/platinum), Snowflake SQL conventions, sqlfluff formatting,
  dbt testing patterns, key macros, and data governance rules. Use this skill
  any time someone asks about writing dbt models, adding data tests, creating
  SQL transformations, fixing pipeline failures, or contributing to the lf-dbt
  repository.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->
<!-- Tool names in this file use Claude Code vocabulary. See docs/tool-mapping.md for other platforms. -->

# LFX Data Engineering

You are generating dbt models and SQL transformations that must be PR-ready. This skill encodes all conventions for the `lf-dbt` repository, which implements a medallion architecture data warehouse on Snowflake.

**Prerequisites:** Snowflake access must be provisioned first (via `/lfx-snowflake-access`).

## Input Validation

Before generating any code, verify your args include:

| Required | If Missing |
|----------|------------|
| Specific task (what to build/modify) | Stop and ask — do not guess |
| Which medallion layer (bronze/silver/gold/platinum) | Infer from task, but confirm |
| Data source name (for bronze) or upstream model (for silver+) | Stop and ask — never assume |
| Target file path(s) | Infer from naming conventions, but verify they exist |
| Example pattern to follow | Find one yourself (see Read Before Generating) |

**If invoked with a FIX: prefix**, this is an error correction. Read the error, find the file, apply the targeted fix, and re-validate.

## Read Before Generating — MANDATORY

Before writing ANY code, you MUST:

1. **Read the target file** (if modifying) — understand what's already there
2. **Read one example file** in the same layer and domain — match the exact patterns
3. **Read the relevant YML test file** — ensure your model will be tested consistently

Do NOT generate code from memory alone. The codebase may have evolved since your training data.

```bash
# Example: before creating a new bronze model, read an existing one in the same source
cat models/bronze/fivetran_platform/bronze_fivetran_platform_events.sql
# And read the test file
cat models/bronze/fivetran_platform/bronze_fivetran_platform_tests.yml
```

## License Header

Every new `.sql` file MUST start with this header:

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT
```

Every new `.yml` file MUST start with:

```yaml
# Copyright The Linux Foundation and each contributor to LFX.
# SPDX-License-Identifier: MIT
```

## Completion Report

When you finish, output a clear summary:

```
═══════════════════════════════════════════
/lfx-data-engineer COMPLETE
═══════════════════════════════════════════
Files created:
  - models/bronze/fivetran_platform/bronze_fivetran_platform_new_table.sql

Files modified:
  - models/bronze/fivetran_platform/bronze_fivetran_platform_tests.yml — added new_table tests

Validation:
  - Ran: sqlfluff lint models/bronze/fivetran_platform/bronze_fivetran_platform_new_table.sql
  - Result: ✓ passed / ✗ failed with: <error>
  - Ran: dbt compile --select bronze_fivetran_platform_new_table
  - Result: ✓ passed / ✗ failed with: <error>

Notes:
  - Source table 'new_table' must exist in the fivetran_platform source definition

Errors:
  - (none)
═══════════════════════════════════════════
```

**Always include the Validation section.** Run `sqlfluff lint` and `dbt compile` after creating or modifying files. Report the result.

---

## Medallion Architecture Quick Reference

| Layer | Materialization | Schema | Purpose |
|-------|----------------|--------|---------|
| **Bronze** | `view` (default) | `bronze_*` (per source) | 1:1 with source data — column renames, type casting, filter deletes/test data |
| **Silver** | `table` | `silver_dim`, `silver_fact` | Business logic, joins, reusable business objects |
| **Gold** | `table` | `gold_*` (per domain) | Aggregated metrics for specific business use cases |
| **Platinum** | `table` | `platinum*` (per product) | Pre-computed reports with time windows for dashboards |

### References

| Task | Reference |
|------|-----------|
| Environment setup, dbt commands, clone workflow | [references/getting-started.md](references/getting-started.md) |
| Detailed layer guide with SQL examples and decision tree | [references/medallion-architecture.md](references/medallion-architecture.md) |
| SQL formatting, keyword casing, indentation, CTEs, JOINs | [references/sql-style-guide.md](references/sql-style-guide.md) |
| dbt test conventions, PII tagging, primary key tests | [references/testing-patterns.md](references/testing-patterns.md) |
| Project macros: smart_source, format_timestamp, date ranges, deltas | [references/key-macros.md](references/key-macros.md) |
| Troubleshooting build failures, sqlfluff, incremental issues | [references/debugging-pipelines.md](references/debugging-pipelines.md) |

---

## Creating a Model by Layer

### Bronze — Source Extraction

Bronze models are 1:1 with source tables. They rename columns, cast types, and filter out deleted/test records. No business logic.

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

SELECT
    id AS event_id,
    event_title AS event_name,
    event_start_date,
    event_end_date,
    created_date AS event_created_ts,
    lastmodified_date AS updated_at

FROM {{ source('fivetran_platform', 'event') }}
WHERE
    NOT _fivetran_deleted
    AND NOT is_test
```

**Bronze rules:**
- Use `source()` to reference raw tables (or `smart_source()` for dev lookback)
- Rename columns to snake_case with business-friendly names
- Timestamps: suffix `_ts`; Dates: suffix `_date`; Booleans: prefix `is_` or `has_`
- Filter `_fivetran_deleted` and test data rows
- No JOINs — one source table per model
- Use `get_warehouse('hourly')` in config if the source is large

### Silver — Business Logic

Silver models join bronze models, apply business rules, and create reusable objects. Split into `dim/` (dimensions) and `fact/` (facts).

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

{% set warehouse = get_warehouse('hourly') %}

{{ config(snowflake_warehouse=warehouse) }}

/*
Purpose:
    Create a reusable project dimension with core Salesforce project attributes
    and the latest project health score for downstream analytics.

Questions answered:
    - What are the canonical identifiers and names for each project?
    - What is the current health score associated with each project?

Data sources:
    - bronze_fivetran_salesforce_projects
    - silver_fact_crowd_dev_project_health_metrics
*/

WITH source_data AS (
    SELECT
        project_id,
        project_name,
        project_slug,
        project_status
    FROM {{ ref('bronze_fivetran_salesforce_projects') }}
),

enriched AS (
    SELECT
        s.project_id,
        s.project_name,
        s.project_slug,
        s.project_status,
        h.health_score
    FROM source_data s
    LEFT JOIN {{ ref('silver_fact_crowd_dev_project_health_metrics') }} h
        ON s.project_slug = h.project_slug
)

SELECT
    project_id,
    project_name,
    project_slug,
    project_status,
    health_score
FROM enriched
```

**Silver rules:**
- Use `ref()` to reference bronze or other silver models
- CTEs for each logical step (one unit of work per CTE)
- Verbose CTE names that describe what they do
- Include a block comment at the top explaining purpose, questions answered, and data sources
- `dim/` for slowly-changing attributes; `fact/` for events and transactions

### Gold — Aggregated Metrics

Gold models combine silver models into purpose-built datasets for specific use cases.

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

{{ config(unique_key=["_key", "project_id"]) }}

SELECT
    ({{ dbt_utils.generate_surrogate_key(["c._key", "p.mapped_project_id"]) }}) AS activity_project_id,
    c._key,
    c.activity_id,
    c.activity_ts,
    p.mapped_project_id AS project_id,
    p.mapped_project_slug AS project_slug

FROM {{ ref("silver_fact_crowd_dev_activities") }} c
LEFT JOIN {{ ref("_silver_dim_project_spine") }} p
    ON c.project_id = p.base_project_id
WHERE
    p.mapped_project_id IS NOT NULL
    AND {{ filter_code_contributions_non_bot('c') }}
```

**Gold rules:**
- Use `dbt_utils.generate_surrogate_key()` for composite primary keys
- Always specify `unique_key` in config for incremental models
- Reference silver models via `ref()`, apply domain-specific macros
- Final SELECT should explicitly list all columns — no `SELECT *`

### Platinum — Pre-Computed Reports

Platinum models produce dashboard-ready data with time-windowed aggregations.

```sql
-- Copyright The Linux Foundation and each contributor to LFX.
-- SPDX-License-Identifier: MIT

{% set warehouse = get_warehouse('hourly') %}

{{ config(snowflake_warehouse=warehouse) }}

WITH base AS (
    SELECT
        user_id,
        event_id,
        event_name,
        event_start_date
    FROM {{ ref('silver_fact_event_registrations') }}
    WHERE event_name IS NOT NULL
)

SELECT
    ({{ dbt_utils.generate_surrogate_key(['user_id', 'event_id']) }}) AS _key,
    user_id,
    event_id,
    event_name,
    event_start_date
FROM base
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_id, event_id
    ORDER BY event_start_date
) = 1
```

**Platinum rules:**
- Use date range macros (`is_last_30_days`, `is_year_to_date`, etc.) for time windows
- Use `get_warehouse()` for resource-intensive models
- `GROUP BY ALL` is acceptable for complex aggregations
- `QUALIFY` with `ROW_NUMBER()` for deduplication
- Purpose-built for specific dashboards (PCC, Individual Dashboard, Org Dashboard)

---

## Writing Tests (YML)

Every model needs a corresponding entry in a `*_tests.yml` file. Use `data_tests:` (not the deprecated `tests:`). Parameterized tests require the `arguments:` wrapper.

```yaml
# Copyright The Linux Foundation and each contributor to LFX.
# SPDX-License-Identifier: MIT

version: 2
models:
  - name: my_new_model
    description: "What this model contains and its purpose."
    columns:
      - name: _key
        description: "The unique primary key for the table."
        data_tests:
          - unique
          - not_null
          - dbt_utils.not_empty_string

      - name: status
        description: "The current status."
        data_type: string
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ["active", "inactive", "pending"]

      - name: project_id
        description: "Foreign key to the projects dimension."
        data_type: string
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('silver_dim_projects')
                field: project_id

      - name: email
        description: "User email address"
        data_type: string
        config:
          meta:
            contains_pii: true
            data_retention: "undefined"
```

See [references/testing-patterns.md](references/testing-patterns.md) for full conventions.

---

## SQL Style Rules (Summary)

| Rule | Example |
|------|---------|
| Uppercase SQL keywords | `SELECT`, `FROM`, `WHERE`, `LEFT JOIN` |
| Lowercase identifiers | `event_id`, `project_name` |
| 4-space indentation | Indent columns under `SELECT`, conditions under `WHERE` |
| Trailing commas | `event_id,` (not `, event_id`) |
| CTEs over subqueries | Use `WITH ... AS (...)` instead of nested `SELECT` |
| Default to `INNER JOIN` | Use `LEFT JOIN` only when right side may have no matches |
| No `RIGHT JOIN` | Rewrite as `LEFT JOIN` |
| No `SELECT DISTINCT` | Requires architect approval |
| `GROUP BY` by number | `GROUP BY 1, 2` preferred over column names |
| Explicit column lists | No `SELECT *` in final SELECT |
| Pre-filter in CTEs | Complex filtering on joined tables belongs in a CTE before the join |

See [references/sql-style-guide.md](references/sql-style-guide.md) for full formatting rules.

---

## Key Macros

| Macro | Purpose | When to Use |
|-------|---------|-------------|
| `smart_source()` | Dev-friendly source wrapper with lookback | Bronze models reading from source tables |
| `format_timestamp()` | Generate UTC `_ts` and local `_ts_local` columns | Bronze models normalizing timestamps |
| `to_utc_timestamp()` | Convert local timestamp to UTC with dynamic timezone | When timezone is a column, not a constant |
| `get_warehouse()` | Select warehouse by size (`default`, `hourly`, `medium`) | Large models needing specific compute |
| `generate_alias_name` | Strips schema prefix from table name (e.g., `silver_dim_` → table name) | Automatic — configured in macros |
| `is_last_7_days()`, `is_last_30_days()`, etc. | Date range filters for time windows | Platinum models with pre-computed periods |
| `is_prev_7_days()`, `is_prev_30_days()`, etc. | Previous period for period-over-period comparison | Delta/change calculations |
| `add_delta_columns()` | Generate `_prev`, `_diff`, `_delta` columns | Period-over-period metric comparisons |
| `get_month()`, `get_quarter()` | Human-readable date labels | Display-friendly date columns |
| `gdpr_filter_email()` | Exclude GDPR-suppressed emails | Any model exposing email addresses |
| `filter_code_contributions_non_bot()` | Exclude bot code contributions | Code contribution models |
| `format_country()` | Normalize country names to canonical values | Models with user-entered country data |
| `comprehensive_email_filter()` | Validate email format + exclude test emails | Email-based models |

See [references/key-macros.md](references/key-macros.md) for full documentation and usage examples.

---

## Data Governance

### PII Tagging

Columns containing personally identifiable information (names, emails, addresses, etc.) must be tagged in the YML file. Use `config.meta` — not top-level `meta`.

```yaml
columns:
  - name: email
    description: "User email address"
    config:
      meta:
        contains_pii: true
        data_retention: "undefined"
```

### Timestamp Normalization

All timestamps must be normalized to UTC in the bronze layer:
- Timestamps: `_ts` suffix, stored as `TIMESTAMP_NTZ` in UTC
- Dates: `_date` suffix, stored as `DATE`
- Use `format_timestamp()` macro for consistent conversion
- Use `convert_timezone()` for explicit timezone conversion

### Primary Key Convention

- Use `_key` suffix for primary key columns
- Always add unique, not_null, and not_empty_string tests

---

## Common Anti-Patterns — DO NOT DO THESE

| Anti-Pattern | Correct Pattern |
|-------------|-----------------|
| Missing license header | Always add `-- Copyright The Linux Foundation...` |
| `tests:` in YML | Use `data_tests:` (dbt v1.10.5+) |
| `meta:` at top level in YML | Nest under `config:` → `meta:` |
| Missing `arguments:` on parameterized tests | `accepted_values:` → `arguments:` → `values:` |
| `tags:` at top level in YML | Nest under `config:` → `tags:` |
| Duplicate `config:` keys in YML | Combine into a single `config:` block |
| Custom keys directly in `config:` | Nest under `config:` → `meta:` |
| `SELECT DISTINCT` | Use `GROUP BY` or `QUALIFY ROW_NUMBER()` |
| `RIGHT JOIN` | Rewrite as `LEFT JOIN` |
| Filtering right side of LEFT JOIN in `WHERE` | Filter in the `ON` clause or in a CTE |
| `SELECT *` in final select | Explicitly list all columns |
| Subqueries in `FROM` or `JOIN` | Use CTEs |
| Raw `source()` in dev (large tables) | Use `smart_source()` with lookback |
| Hardcoded warehouse name | Use `get_warehouse()` macro |
| `console.log` / `print` debugging | Use `dbt compile` and `dbt show` |
| Committing without `--signoff` or `-S` | Always use signed commits with DCO |

---

## Pre-PR Checklist

### All Models
- [ ] License header on all new `.sql` and `.yml` files
- [ ] Model documented in corresponding `*_tests.yml` file
- [ ] Primary key column(s) have `unique`, `not_null`, `dbt_utils.not_empty_string` tests
- [ ] PII columns tagged with `config.meta.contains_pii: true` and `data_retention: "undefined"`
- [ ] `sqlfluff lint` passes on all new/modified `.sql` files
- [ ] `dbt compile --select +model_name` succeeds
- [ ] Column naming follows conventions (`_ts`, `_date`, `is_`, `has_`, `_key`)
- [ ] No `SELECT *` in final select statements
- [ ] All timestamps normalized to UTC

### Bronze Models
- [ ] 1:1 with source table — no joins
- [ ] Filters `_fivetran_deleted` and test data
- [ ] Column renames to snake_case with business-friendly names
- [ ] Uses `source()` or `smart_source()`

### Silver Models
- [ ] Uses `ref()` to reference upstream models
- [ ] CTEs for each logical unit of work
- [ ] Block comment explaining purpose and data sources
- [ ] Placed in correct subfolder (`dim/` or `fact/`)

### Gold Models
- [ ] Surrogate key generated for composite keys
- [ ] `unique_key` specified in config for incremental models
- [ ] Final SELECT explicitly lists all columns

### Platinum Models
- [ ] Uses date range macros for time windows
- [ ] `get_warehouse()` configured if resource-intensive
- [ ] Purpose-built for a specific dashboard or use case

---

## Scope Boundaries

**This skill DOES:**
- Generate/modify dbt SQL models following medallion architecture
- Create/update YML test files with proper data_tests format
- Add source definitions for new data sources
- Apply project macros (smart_source, format_timestamp, date ranges, etc.)
- Run sqlfluff lint/fix validation after changes
- Run dbt compile to verify model correctness

**This skill does NOT:**
- Run dbt build/test against the warehouse (use the `running-dbt-commands` skill)
- Modify existing macros without architect review
- Make architectural decisions about layer placement (ask the user)
- Generate semantic layer definitions (use the `building-dbt-semantic-layer` skill)
- Troubleshoot dbt Cloud job failures (use the `troubleshooting-dbt-job-errors` skill)
- Modify protected infrastructure files (`dbt_project.yml`, `profiles.yml`, `packages.yml`) — flag for code owner
