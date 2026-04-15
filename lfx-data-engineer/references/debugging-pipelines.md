<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Debugging Pipelines

Common failure patterns in the lf-dbt project and how to resolve them.

---

## dbt compile Failures

`dbt compile` validates SQL and Jinja syntax without executing against
Snowflake. Always run it before `dbt build`.

```bash
dbt compile --select +model_name
```

### Missing `ref()` or `source()` Target

**Error:** `Compilation Error: ... depends on a node named '...' which was not found`

**Cause:** The model references a table or source that doesn't exist.

**Fix:**
1. Check spelling — model names must match exactly (case-sensitive in YAML)
2. Verify the upstream model exists: `find models -name '*model_name*'`
3. For sources, check the source definition YAML file exists
4. Run `dbt deps` if the reference is to a package model

### Jinja Syntax Error

**Error:** `Compilation Error: ... unexpected '}'` or `expected token 'end of statement block'`

**Cause:** Malformed Jinja template syntax.

**Fix:**
1. Check for unmatched `{% %}` or `{{ }}` blocks
2. Verify macro calls have the right number of arguments
3. Look for missing commas in macro arguments
4. Check that `config()` blocks have proper Python dict syntax

### Undefined Macro

**Error:** `Compilation Error: 'macro_name' is undefined`

**Cause:** The macro doesn't exist or packages aren't installed.

**Fix:**
1. Run `dbt deps` to install packages
2. Check macro spelling — search `macros/` for the correct name
3. Verify the macro is defined in `macros/` or in a package

---

## dbt build Failures

### SQL Compilation Error in Snowflake

**Error:** `Database Error: ... SQL compilation error`

**Cause:** The generated SQL is invalid Snowflake syntax.

**Fix:**
1. Inspect the compiled SQL: `dbt compile --select model_name`
2. Open the compiled file: `target/compiled/core_warehouse/models/.../model_name.sql`
3. Copy the compiled SQL into a Snowflake worksheet and run it directly
4. The Snowflake error message will point to the exact line

### Missing Source Table

**Error:** `Database Error: ... Object 'DATABASE.SCHEMA.TABLE' does not exist`

**Cause:** The source table hasn't been cloned to your dev schema.

**Fix:**
```bash
# Clone production tables to dev
dbt run-operation clone_production_tables

# Then rebuild excluding cloned data
dbt build --select +model_name --exclude tag:cloned_data
```

### Permission Error

**Error:** `Database Error: ... Insufficient privileges to operate on ...`

**Cause:** Your Snowflake role doesn't have access to the source data.

**Fix:**
1. Verify your role in `.env` matches your provisioned access
2. Check if the source table requires a specific role
3. Contact CloudOps if you need additional permissions

---

## sqlfluff Lint Errors

### Running the Linter

```bash
# Lint a file and see errors
sqlfluff lint path/to/file.sql

# Auto-fix what it can
sqlfluff fix path/to/file.sql

# Lint all staged files
make lint-staged-files
```

### Common Lint Errors

| Error Code | Description | Fix |
|------------|-------------|-----|
| `CP01` | Keyword not uppercase | Change `select` to `SELECT` |
| `CP02` | Identifier not lowercase | Change `COLUMN_NAME` to `column_name` |
| `CP03` | Function not uppercase | Change `count()` to `COUNT()` |
| `CP04` | Literal not uppercase | Change `null` to `NULL`, `true` to `TRUE` |
| `CP05` | Type cast not lowercase | Change `::INT` to `::int` |
| `CV09` | Blocked data type | Use `INT` not `INTEGER`, `DECIMAL` not `NUMBER` |
| `CV11` | Non-shorthand cast | Use `::int` not `CAST(x AS INT)` |
| `ST05` | Subquery in FROM/JOIN | Extract to a CTE |
| `RF03` | Qualified single-table ref | Remove table alias prefix when only one table |
| `AL01` | Implicit table alias style | `FROM users u` is fine (project allows implicit) |

### Ignoring Specific Rules

If a specific lint rule must be violated with good reason:

```sql
-- Example: using a blocked type because the source requires it
column_name::NUMBER  -- noqa: CV09 - source returns NUMBER type
```

### Jinja Template Errors in sqlfluff

**Error:** `WARNING: Could not parse ... Traceback ...`

**Cause:** sqlfluff can't parse a Jinja expression.

**Fix:**
1. Ensure `dbt deps` has been run (macros from packages are needed)
2. Check that `load_macros_from_path = macros` is in `.sqlfluff`
3. Complex Jinja may need `-- noqa` to skip that line

---

## Incremental Model Issues

### Full Refresh

If an incremental model has bad data or schema changes:

```bash
# Rebuild from scratch (drops and recreates)
dbt build --select model_name --full-refresh
```

### Unique Key Conflicts

**Error:** `Database Error: ... Duplicate row detected during DML action`

**Cause:** The `unique_key` in the model config doesn't produce unique rows.

**Fix:**
1. Check the `unique_key` in the model's `config()` block
2. Run `dbt show` to inspect for duplicates:

```bash
dbt show --select model_name --limit 20
```

3. Add `QUALIFY ROW_NUMBER()` to deduplicate before the final SELECT
4. If the issue is in source data, add deduplication in a CTE

### Schema Changes

If you add or remove columns from an incremental model:

```bash
# Full refresh to apply schema changes
dbt build --select model_name --full-refresh
```

Without `--full-refresh`, new columns won't appear because the existing table
structure is preserved for incremental loads.

---

## Quick Data Validation

### `dbt show` — Preview Results

Preview the output of a model without materializing it:

```bash
# Show first 5 rows (default)
dbt show --select model_name

# Show more rows
dbt show --select model_name --limit 20

# Show with inline SQL
dbt show --inline "SELECT COUNT(*) FROM {{ ref('model_name') }}"
```

### `dbt compile` — Inspect Generated SQL

See exactly what SQL dbt will execute:

```bash
dbt compile --select model_name
```

The compiled SQL is written to:
`target/compiled/core_warehouse/models/.../model_name.sql`

Open this file to see the fully-rendered SQL with all Jinja resolved.

---

## Missing Data in Dev

### Symptom: Model Runs But Returns No Rows

**Cause:** The `smart_source()` macro limits data to the last 30 days in dev.
If the source table has no recent data, the query returns nothing.

**Fix:**
1. Increase the lookback window: `smart_source('source', 'table', 'date_col', 90)`
2. Or clone production data:

```bash
dbt run-operation clone_production_tables
dbt build --select +model_name --exclude tag:cloned_data
```

### Symptom: Source Table Not Found

**Cause:** Large tables (Kafka, Salesforce) aren't rebuilt in dev by default.

**Fix:** Clone production data (see above). The cloned tables/views appear in
your dev schema automatically.

---

## Test Failures

### Running Tests

```bash
# Run all tests
dbt test

# Test a specific model
dbt test --select model_name

# Test a model and all its dependencies
dbt test --select +model_name
```

### Debugging a Failed Test

1. Read the test failure message — it tells you which test and column failed
2. Check the compiled test SQL: `target/compiled/core_warehouse/tests/...`
3. Run the test query directly in Snowflake to see the offending rows
4. Use `dbt show` to inspect the model output:

```bash
dbt show --inline "
SELECT column_name, COUNT(*)
FROM {{ ref('model_name') }}
GROUP BY 1
HAVING COUNT(*) > 1
"
```

### Known Edge Cases

Some models have intentional test threshold overrides for known data quality
issues:

```yaml
data_tests:
  - unique:
      config:
        error_if: ">10"
        warn_if: ">10"
```

If your model has a small number of expected duplicates from upstream data,
use this pattern with a comment explaining why.

---

## dbt Cloud Job Failures

For failures in dbt Cloud (production or staging jobs), use the
`troubleshooting-dbt-job-errors` skill in the lf-dbt repository's
`.agents/skills/` directory. That skill covers:

- Reading job run logs via the dbt Cloud Admin API
- Diagnosing intermittent failures
- Checking git history for recent changes that may have caused the failure
- Investigating data issues in source systems

---

## Common Debugging Workflow

```text
1. dbt compile --select model_name
   └─ Fix Jinja/SQL syntax errors

2. sqlfluff lint path/to/model.sql
   └─ Fix formatting violations

3. dbt build --select model_name
   └─ Fix Snowflake runtime errors

4. dbt test --select model_name
   └─ Fix data quality issues

5. dbt show --select model_name --limit 20
   └─ Verify output looks correct
```
