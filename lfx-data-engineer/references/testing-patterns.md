<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# dbt Testing Patterns

This guide covers the test conventions for the lf-dbt project, aligned with
dbt v1.10.5+. All models must have corresponding tests in a `*_tests.yml` file
co-located in the same directory as the model.

## Test File Structure

Test files use `version: 2` and the `models:` key. Each model entry includes
a description and column definitions with data types and tests.

```yaml
# Copyright The Linux Foundation and each contributor to LFX.
# SPDX-License-Identifier: MIT

version: 2
models:
  - name: bronze_fivetran_platform_events
    description: "Event data from the Fivetran Platform source."
    config:
      tags:
        - "events"
    columns:
      - name: event_id
        description: "Unique identifier for the event."
        data_type: string
        data_tests:
          - unique
          - not_null

      - name: event_name
        description: "The name of the event."
        data_type: string
        data_tests:
          - not_null
          - dbt_utils.not_empty_string

      - name: event_start_date
        description: "The start date of the event."
        data_type: timestamp_tz
        data_tests:
          - not_null
```

---

## Key Rules

### Use `data_tests:` (not `tests:`)

The `tests:` key is deprecated in dbt v1.10.5+. Always use `data_tests:`.

```yaml
# CORRECT
columns:
  - name: event_id
    data_tests:
      - unique
      - not_null

# WRONG (deprecated)
columns:
  - name: event_id
    tests:
      - unique
      - not_null
```

### Use `arguments:` for Parameterized Tests

Tests that accept parameters (like `accepted_values`, `relationships`) must
wrap their arguments under the `arguments:` property.

```yaml
# CORRECT
columns:
  - name: status
    data_tests:
      - accepted_values:
          arguments:
            values: ["active", "inactive", "pending"]

  - name: project_id
    data_tests:
      - relationships:
          arguments:
            to: ref('silver_dim_projects')
            field: project_id

# WRONG (missing arguments: wrapper)
columns:
  - name: status
    data_tests:
      - accepted_values:
          values: ["active", "inactive", "pending"]
```

Simple tests without arguments (`unique`, `not_null`, `dbt_utils.not_empty_string`)
do NOT need the `arguments:` wrapper.

---

## Primary Key Tests

Every column named `_key` or `_pk` must have these three tests:

```yaml
columns:
  - name: _key
    description: "The unique primary key for the table."
    data_tests:
      - unique
      - not_null
      - dbt_utils.not_empty_string
```

This pattern is enforced across all layers.

---

## PII Tagging

Columns containing personally identifiable information must be tagged using
`config.meta`. Do NOT put `meta` at the top level — it must be nested inside
`config`.

```yaml
# CORRECT
columns:
  - name: email
    description: "User email address"
    data_type: string
    config:
      meta:
        contains_pii: true
        data_retention: "undefined"

# WRONG (meta at top level — triggers deprecation warnings)
columns:
  - name: email
    description: "User email address"
    meta:
      contains_pii: true
      data_retention: "undefined"
```

Always include `data_retention: "undefined"` when adding a `contains_pii` tag.

Do NOT duplicate PII information across `tags` and `meta`:

```yaml
# WRONG (redundant — tags and meta both indicate PII)
columns:
  - name: email
    config:
      tags:
        - "contains_pii"
      meta:
        contains_pii: true
        data_retention: "undefined"

# CORRECT (meta is the single source of truth)
columns:
  - name: email
    config:
      meta:
        contains_pii: true
        data_retention: "undefined"
```

### What Counts as PII

- Full, first, middle, or last name
- Email addresses
- Phone numbers
- Physical addresses
- Government IDs (SSN, passport numbers)
- Financial information

---

## Model-Level Configuration

Tags and meta at the model level also go under `config:`:

```yaml
models:
  - name: my_model
    description: "Model description"
    config:
      tags:
        - "events"
      meta:
        contains_pii: false
        data_retention: "undefined"
    columns:
      - name: _key
        data_tests:
          - unique
          - not_null
```

Never define `config:` twice in the same block:

```yaml
# WRONG (duplicate config key)
models:
  - name: my_model
    config:
      tags:
        - "events"
    config:
      contract: { enforced: true }

# CORRECT (single config block)
models:
  - name: my_model
    config:
      tags:
        - "events"
      contract: { enforced: true }
```

---

## Test Configuration

Use `config:` for test-level settings like `where`, `severity`, and error
thresholds. Custom keys must go in `config.meta`:

```yaml
columns:
  - name: order_id
    data_tests:
      - unique:
          config:
            error_if: ">10"
            warn_if: ">10"
      - not_null
      - accepted_values:
          arguments:
            values: ["placed", "shipped", "completed", "returned"]
          config:
            where: "order_date >= CURRENT_DATE - INTERVAL '30 days'"
            meta:
              severity: warn
```

---

## Common Test Types

### Simple Tests (no arguments needed)

```yaml
data_tests:
  - unique
  - not_null
  - dbt_utils.not_empty_string
```

### Accepted Values

```yaml
data_tests:
  - accepted_values:
      arguments:
        values: ["Active", "Completed", "Cancelled", "Pending"]
```

### Relationships (Foreign Keys)

```yaml
data_tests:
  - relationships:
      arguments:
        to: ref('silver_dim_projects')
        field: project_id
```

### Custom Error Thresholds

For known edge cases where a few duplicates are expected:

```yaml
data_tests:
  - unique:
      config:
        error_if: ">10"
        warn_if: ">10"
```

---

## Unit Tests

For unit tests, use the `unit_tests:` key. Custom keys like `severity` must
go in `config.meta`:

```yaml
unit_tests:
  - name: test_my_model_logic
    model: my_model
    config:
      meta:
        severity: warn
    given:
      - input: ref('source_model')
        rows:
          - { id: "123", status: "active" }
          - { id: "456", status: "inactive" }
    expect:
      rows:
        - { id: "123", status: "active" }
```

For detailed unit test patterns, see the `adding-dbt-unit-test` skill in the
lf-dbt repository's `.agents/skills/` directory.

---

## Test File Organization

Test files are co-located with models and follow this naming convention:

| Layer | Test File |
|-------|-----------|
| Bronze | `models/bronze/{source}/bronze_{source}_tests.yml` |
| Silver | `models/silver/dim/silver_dim_tests.yml` or `models/silver/fact/silver_fact_tests.yml` |
| Gold | `models/gold/fact/gold_fact_tests.yml` |
| Platinum | `models/platinum/platinum_tests.yml` or per-folder |

Some layers use a single consolidated test file (like `silver_dim_tests.yml`),
while others have per-source test files. Check the existing pattern in the
target directory and follow it.

---

## Checklist for New Tests

- [ ] License header at top of YML file
- [ ] `version: 2` declared
- [ ] `data_tests:` used (not deprecated `tests:`)
- [ ] `arguments:` wrapper on parameterized tests
- [ ] Primary key columns have `unique`, `not_null`, `dbt_utils.not_empty_string`
- [ ] PII columns tagged with `config.meta.contains_pii: true`
- [ ] `data_retention: "undefined"` included with PII tags
- [ ] `meta` and `tags` nested under `config:` (not at top level)
- [ ] No duplicate `config:` keys in the same block
- [ ] Custom keys nested in `config.meta` (not directly in `config`)
- [ ] Column `data_type` specified for key columns
- [ ] Descriptions provided for all columns
