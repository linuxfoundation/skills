<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# SQL Style Guide

This guide consolidates the formatting rules enforced by `.sqlfluff` and the
project's coding standards. All SQL files must pass `sqlfluff lint` before
being committed.

## Keyword and Identifier Casing

| Element | Casing | Example |
|---------|--------|---------|
| SQL keywords | UPPERCASE | `SELECT`, `FROM`, `WHERE`, `LEFT JOIN`, `GROUP BY` |
| Column names | lowercase | `event_id`, `project_name`, `created_ts` |
| Table aliases | lowercase | `FROM users u`, `JOIN projects p` |
| Functions | UPPERCASE | `SUM()`, `COUNT()`, `COALESCE()`, `ROW_NUMBER()` |
| Literals | UPPERCASE | `TRUE`, `FALSE`, `NULL` |
| Type casts | lowercase shorthand | `::int`, `::string`, `::date` (not `CAST()`) |

## Indentation

- Use **4 spaces** (not tabs)
- Do not right-align aliases
- Use **trailing commas** in SELECT statements

```sql
-- CORRECT
SELECT
    user_id,
    user_name,
    email,
    created_ts

-- WRONG (leading commas)
SELECT
    user_id
    , user_name
    , email
    , created_ts

-- WRONG (right-aligned aliases)
SELECT
    userId                                as user_id,
    convert_timezone('UTC', createdDate)  as created_date
```

## SELECT Statements

- Fields should be stated before aggregates and window functions
- Group-by columns are always listed first in the SELECT
- Final SELECT must explicitly list all columns — no `SELECT *`
- `SELECT DISTINCT` is not allowed (requires architect approval)
- Use `GROUP BY` or `QUALIFY ROW_NUMBER()` instead of `DISTINCT`

```sql
-- CORRECT: explicit columns, group-by fields first
SELECT
    project_id,
    project_name,
    COUNT(*) AS total_events,
    SUM(revenue) AS total_revenue
FROM events
GROUP BY 1, 2

-- WRONG: SELECT *
SELECT * FROM events
```

## GROUP BY and ORDER BY

- Prefer ordering and grouping **by number**: `GROUP BY 1, 2`
- If grouping by more than a few columns, reconsider the model design
- `GROUP BY ALL` is acceptable in platinum models for complex aggregations

```sql
-- CORRECT
GROUP BY 1, 2, 3

-- ACCEPTABLE in platinum models
GROUP BY ALL
```

## JOINs

- **Default to INNER JOIN** — use LEFT JOIN only when the right side may have
  no matches and you still want rows from the left
- **RIGHT JOIN is not allowed** — rewrite as LEFT JOIN
- Specify join keys explicitly — **do not use `USING`** (Snowflake has
  inconsistencies with `USING` results)
- When joining two or more tables, always **prefix columns with the table alias**
- Pre-filter complex conditions in a CTE before the join
- Do **not** filter on the right side of a LEFT JOIN in the `WHERE` clause
  (this negates the LEFT JOIN). Filter in the `ON` clause or in a CTE.

```sql
-- CORRECT: filter in ON clause
SELECT
    l.user_id,
    r.event_name
FROM users l
LEFT JOIN events r
    ON l.user_id = r.user_id
    AND r.event_status = 'Active'

-- WRONG: filtering right side in WHERE (turns LEFT JOIN into INNER JOIN)
SELECT
    l.user_id,
    r.event_name
FROM users l
LEFT JOIN events r
    ON l.user_id = r.user_id
WHERE
    r.event_status = 'Active'

-- WRONG: using USING
FROM users u
JOIN events e USING (user_id)
```

## CTEs (Common Table Expressions)

- Use CTEs instead of subqueries in `FROM` or `JOIN` clauses (enforced by
  sqlfluff rule `ST05`)
- Each CTE should perform a **single, logical unit of work**
- CTE names should be **verbose** enough to convey what they do
- CTEs with confusing or notable logic should have a comment
- CTEs duplicated across models should be pulled into their own models or macros

```sql
-- CORRECT: CTEs for logical units
WITH active_events AS (
    SELECT
        event_id,
        event_name,
        event_start_date
    FROM {{ ref('bronze_fivetran_platform_events') }}
    WHERE event_status = 'Active'
),

event_registrations AS (
    SELECT
        event_id,
        COUNT(*) AS registration_count
    FROM {{ ref('silver_fact_event_registrations') }}
    GROUP BY 1
)

SELECT
    e.event_id,
    e.event_name,
    e.event_start_date,
    COALESCE(r.registration_count, 0) AS registration_count
FROM active_events e
LEFT JOIN event_registrations r
    ON e.event_id = r.event_id

-- WRONG: subquery in FROM
SELECT *
FROM (
    SELECT event_id, event_name
    FROM events
    WHERE event_status = 'Active'
) e
```

## Table Aliasing

- Use the `AS` keyword when aliasing columns
- Table aliases do not require `AS` (implicit aliasing is allowed)
- When selecting from a single table, do **not** prefix columns with the alias

```sql
-- CORRECT: single table, no prefix
SELECT
    user_id,
    user_name,
    email
FROM users

-- CORRECT: multiple tables, always prefix
SELECT
    u.user_id,
    u.user_name,
    e.event_name
FROM users u
INNER JOIN events e
    ON u.user_id = e.organizer_id
```

## CASE Statements

- `CASE` and `END` on their own lines
- Conditions indented inside the block
- Multiple boolean conditions on separate lines

```sql
-- CORRECT
CASE
    WHEN status = 'Active'
    AND is_verified = TRUE
    THEN 'Active Verified'
    WHEN status = 'Inactive'
    THEN 'Inactive'
    ELSE 'Unknown'
END AS status_label,
```

## WHERE Clauses

- Single conditions can be inline: `WHERE event_status = 'Active'`
- Multiple conditions on separate lines, indented
- `OR` conditions enclosed in parentheses

```sql
-- CORRECT: multiple conditions
WHERE
    event_status = 'Active'
    AND event_start_date >= CURRENT_DATE()
    AND (
        event_type = 'Conference'
        OR event_type = 'Meetup'
    )
```

## Data Types

The project normalizes data types. These names are **blocked** by sqlfluff:

| Blocked Type | Use Instead |
|-------------|-------------|
| `NUMBER`, `NUMERIC` | `DECIMAL` |
| `INTEGER`, `BIGINT`, `SMALLINT`, `TINYINT`, `BYTEINT` | `INT` |
| `DOUBLE`, `REAL` | `FLOAT` |
| `CHARACTER` | `CHAR` |
| `DATETIME` | `TIMESTAMP_NTZ` |

If an exception is required, add `-- noqa: L062` with a comment explaining why.

## Type Casting

Use shorthand casting (enforced by sqlfluff):

```sql
-- CORRECT
column_name::int
column_name::date
column_name::string

-- WRONG
CAST(column_name AS INT)
CONVERT(INT, column_name)
```

## Newlines and Readability

**DO NOT OPTIMIZE FOR A SMALLER NUMBER OF LINES OF CODE.**
Newlines are cheap; brain time is expensive.

- Long lines should be broken up if it improves readability
- Any clause with more than one item should be listed on new lines, indented
- Conform to the existing style in a file, even if it contradicts this guide

## Running sqlfluff

```bash
# Lint a specific file
sqlfluff lint models/bronze/fivetran_platform/bronze_fivetran_platform_events.sql

# Auto-fix formatting issues
sqlfluff fix models/bronze/fivetran_platform/bronze_fivetran_platform_events.sql

# Lint via Makefile
make lint-fix file=models/bronze/fivetran_platform/bronze_fivetran_platform_events.sql

# Lint all staged files before commit
make lint-staged-files

# Auto-fix all staged files
make fix-lint-staged-files
```

sqlfluff uses the `.sqlfluff` configuration at the repo root. Key settings:

- Dialect: Snowflake
- Templater: dbt (understands `ref()`, `source()`, Jinja)
- No max line length
- Macros loaded from `macros/` directory
- Subqueries forbidden in `FROM` and `JOIN` (use CTEs)
