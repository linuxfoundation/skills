<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Key Macros Reference

The lf-dbt project includes reusable macros in the `macros/` directory. This
reference covers the macros developers use most frequently.

---

## Source and Environment Macros

### `smart_source(source_name, table_name, timestamp_col, lookback_window)`

**File:** `macros/smart_source.sql`

A development-friendly wrapper around `source()` that limits data volume in
non-production environments.

| Environment | Behavior |
|-------------|----------|
| `no_data` (CI) | Wraps source in `WHERE 1=0` — validates schema only, no data |
| Dev (with `timestamp_col`) | Filters to last N days (default 30) for faster builds |
| `prod` / `stage` | Returns raw `source()` reference — full data |

**Usage:**

```sql
-- Bronze model with dev lookback on a timestamp column
FROM {{ smart_source('fivetran_platform', 'event', 'created_date', 30) }}

-- Without timestamp lookback (full table in all environments except CI)
FROM {{ smart_source('fivetran_platform', 'event') }}
```

**When to use:** Bronze models reading from large source tables. Use instead of
raw `source()` when the source has a timestamp column suitable for filtering.

---

### `get_warehouse(warehouse_type)`

**File:** `macros/get_environment_warehouse.sql`

Selects the appropriate Snowflake warehouse based on model size and environment.

| `warehouse_type` | Production Warehouse | Dev/CI Override |
|-------------------|---------------------|-----------------|
| `'default'` | `DBT_PROD` | `DBT_DEV` (dev), `DBT_STG` (CI) |
| `'hourly'` | `DBT_HOURLY` | `DBT_DEV` (dev), `DBT_STG` (CI) |
| `'medium'` | `DBT_PROD_MED` | `DBT_DEV` (dev), `DBT_STG` (CI) |

**Convenience macros:**

- `get_environment_warehouse()` — alias for `get_warehouse('default')`
- `get_hourly_warehouse()` — alias for `get_warehouse('hourly')`
- `get_medium_warehouse()` — alias for `get_warehouse('medium')`

**Usage:**

```sql
{% set warehouse = get_warehouse('hourly') %}

{{ config(snowflake_warehouse=warehouse) }}

SELECT ...
```

**When to use:** Any model that reads from large tables or performs heavy
aggregations. Most bronze and platinum models use `get_warehouse('hourly')`.

---

### `generate_alias_name` / `generate_schema_name`

**File:** `macros/generate_alias_name.sql`, `macros/generate_schema_name.sql`

These macros control how dbt resolves table names in Snowflake.

**`generate_alias_name`** strips the schema prefix from the model name. A model
named `silver_dim_users.sql` configured with `+schema: silver_dim` becomes
table `USERS` (not `SILVER_DIM_USERS`) in the `SILVER_DIM` schema.

**`generate_schema_name`** handles environment-specific schema naming:
- Production: uses the schema name directly (e.g., `SILVER_DIM`)
- Dev: prepends your personal schema (e.g., `your_schema_SILVER_DIM`)

These macros run automatically — you do not call them in model code. But
understanding them is important for knowing where your tables will land.

---

## Timestamp and Date Macros

### `format_timestamp(original_column_name, target_column_name, data_type, local_tz, source_tz)`

**File:** `macros/format_timestamp.sql`

Generates standardized timestamp/date columns with proper naming conventions.

| `data_type` | Output Columns |
|-------------|---------------|
| `'date'` | `{target_column_name}_date` (via `TO_DATE()`) |
| `'timestamp'` | `{target_column_name}_ts` (UTC) + `{target_column_name}_ts_local` (local timezone) |

**Usage:**

```sql
SELECT
    {{ format_timestamp('created_at', 'created', 'timestamp', 'America/New_York') }},
    {{ format_timestamp('birth_date', 'birth', 'date', 'UTC') }}
FROM {{ source('my_source', 'my_table') }}
```

**Produces:**

```sql
convert_timezone('UTC', 'UTC', created_at) AS created_ts,
convert_timezone('UTC', 'America/New_York', created_at) AS created_ts_local,
to_date(birth_date) AS birth_date
```

**When to use:** Bronze models normalizing timestamps from source systems.

---

### `to_utc_timestamp(local_ts, local_tz)`

**File:** `macros/format_timestamp.sql`

Converts a local timestamp to UTC when the timezone is stored in a column
rather than being a constant.

**Usage:**

```sql
SELECT
    {{ to_utc_timestamp('event_start_time', 'event_timezone') }} AS event_start_ts
FROM {{ ref('bronze_events') }}
```

**When to use:** When the timezone varies per row (e.g., events in different
timezones with the timezone stored as a column value).

---

## Date Range Filter Macros

**File:** `macros/date_range_helpers.sql`

These macros generate `WHERE` clause conditions for time-windowed filtering.
They are the backbone of platinum models that pre-compute metrics over specific
time periods.

### Current-Period Macros (Exclude Today by Default)

| Macro | Window |
|-------|--------|
| `is_last_x_days(date, days)` | Generic N-day lookback |
| `is_last_7_days(date)` | Last 7 days (days -8 to -1) |
| `is_last_14_days(date)` | Last 14 days |
| `is_last_30_days(date)` | Last 30 days |
| `is_last_90_days(date)` | Last 90 days |
| `is_last_6_months(date)` | Last 6 calendar months |
| `is_last_12_months(date)` | Last 12 calendar months |
| `is_last_24_months(date)` | Last 24 calendar months |
| `is_last_48_months(date)` | Last 48 calendar months |
| `is_last_quarter(date)` | Most recently completed quarter |
| `is_year_to_date(date)` | Jan 1 of current year through yesterday |
| `is_current_year(date)` | Full current calendar year |
| `is_specific_year(date, year)` | A specific calendar year |
| `is_alltime(date)` | All dates up to today |
| `is_before_today(date)` | Strictly before today |
| `is_before_or_today(date)` | Up to and including today |

**Usage:**

```sql
-- Filter to last 30 days
WHERE {{ is_last_30_days('activity_date') }}

-- Filter to year-to-date
WHERE {{ is_year_to_date('event_start_date') }}

-- Generic lookback
WHERE {{ is_last_x_days('created_ts', 60) }}
```

### Completed Year Macros

| Macro | Window |
|-------|--------|
| `is_last_completed_year(date)` | Previous full calendar year |
| `is_prev_completed_year(date)` | 2 years ago (full year) |
| `is_3rd_last_completed_year(date)` | 3 years ago |
| `is_4th_last_completed_year(date)` | 4 years ago |
| `is_5th_last_completed_year(date)` | 5 years ago |

### Quarter Macros

| Macro | Window |
|-------|--------|
| `is_last_x_quarters(date, quarters)` | Last N completed quarters |
| `is_x_quarters_ago(date, quarters)` | A single completed quarter N quarters ago |
| `is_current_quarter(date)` | Current calendar quarter (from `date_range_helpers_surveys.sql`) |

### Cumulative / "Up To" Macros

| Macro | Window |
|-------|--------|
| `is_up_to_year_to_date(date)` | Everything before today |
| `is_up_to_last_completed_year(date)` | Everything through end of last year |
| `is_up_to_prev_completed_year(date)` | Everything through end of 2 years ago |

---

### Previous-Period Macros (for Period-over-Period Comparisons)

These macros define the period immediately before the corresponding
`is_last_*` window, enabling percent-change and delta calculations.

| Macro | Window |
|-------|--------|
| `is_prev_7_days(date)` | Days -14 to -8 (the week before `is_last_7_days`) |
| `is_prev_14_days(date)` | Days -28 to -15 |
| `is_prev_30_days(date)` | Days -60 to -31 |
| `is_prev_90_days(date)` | Days -180 to -91 |
| `is_prev_6_months(date)` | Months -12 to -7 |
| `is_prev_12_months(date)` | Months -24 to -13 |
| `is_prev_24_months(date)` | Months -48 to -25 |
| `is_prev_quarter(date)` | The quarter before `is_last_quarter` |
| `is_prev_year_to_date(date)` | Same YTD window, shifted back one year (handles leap years) |

**Usage:**

```sql
-- Current period
SUM(CASE WHEN {{ is_last_30_days('activity_date') }} THEN 1 ELSE 0 END) AS last_30_days_count,

-- Previous period for comparison
SUM(CASE WHEN {{ is_prev_30_days('activity_date') }} THEN 1 ELSE 0 END) AS prev_30_days_count
```

---

### "Through Today" Variants

These macros shift the window to include today. Used primarily by social
listening models. The day count stays the same but the window slides forward
by one day.

| Macro | Window |
|-------|--------|
| `is_last_7_days_through_today(date)` | Days -6 to 0 (includes today) |
| `is_last_30_days_through_today(date)` | Days -29 to 0 |
| `is_last_90_days_through_today(date)` | Days -89 to 0 |
| `is_last_12_months_through_today(date)` | 12 months back through today |
| `is_year_to_date_through_today(date)` | Jan 1 through today |

Matching previous-period macros exist:
`is_prev_7_days_through_today(date)`, `is_prev_30_days_through_today(date)`, etc.

---

### Month-Overlap Macros

For monthly-grain data where you need to check if a month falls within a window:

| Macro | Purpose |
|-------|---------|
| `month_overlaps_last_x_days(date, days)` | Does the month containing `date` overlap the last N days? |
| `month_overlaps_last_x_months(date, months)` | Does the month containing `date` overlap the last N months? |

---

### Unified Time Range Filter

```sql
-- Filters based on a time_range_name column
WHERE {{ time_range_filter('date_column', 'time_range_column') }}
```

Supports `'past_365_days'`, `'past_2_years'`, and `'alltime'` values. Used by
ecosystem influence models.

---

## Date/Time Formatting Macros

**File:** `macros/format_helpers.sql`

### `get_short_month(date)`

Returns 3-letter month abbreviation: `'Jan'`, `'Feb'`, ..., `'Dec'`

### `get_month(date)`

Returns full month name: `'January'`, `'February'`, ..., `'December'`

### `get_quarter(date)`

Returns quarter label: `'Q1'`, `'Q2'`, `'Q3'`, `'Q4'`

**Usage:**

```sql
SELECT
    {{ get_month('event_start_date') }} AS event_month,
    {{ get_quarter('event_start_date') }} AS event_quarter,
    {{ get_short_month('event_start_date') }} AS event_month_short
FROM {{ ref('silver_dim_events') }}
```

---

## Delta / Period-over-Period Comparison Macros

**File:** `macros/delta_helpers.sql`

### `add_delta_columns(metrics)`

Generates `_prev`, `_diff`, and `_delta` (percent change) columns for a list
of metric names. Expects the query to have `curr.*` and `prev.*` aliases.

**Usage:**

```sql
SELECT
    curr.project_id
    {{ add_delta_columns(['total_commits', 'total_contributors', 'total_prs']) }}
FROM current_period curr
LEFT JOIN previous_period prev
    ON curr.project_id = prev.project_id
```

**Produces** (for each metric):
- `total_commits` — current value
- `total_commits_prev` — previous period value
- `total_commits_diff` — absolute difference
- `total_commits_delta` — percent change (100% if previous was 0)

### `add_share_of_total(metrics)`

Generates `_share` (percent of total) and `_total_delta` columns.

---

## Data Quality and Filtering Macros

### `gdpr_filter_email(email_field)`

**File:** `macros/gdpr_filter.sql`

Excludes rows where the email matches a GDPR suppression or deletion request.

```sql
WHERE {{ gdpr_filter_email('u.email') }}
```

### `gdpr_filter_email_list(email_list_field, delimiter)`

Filters rows where any email in a delimited list matches a GDPR request.
Supports `;`, `,`, `:`, `|` delimiters.

```sql
WHERE {{ gdpr_filter_email_list('cc_emails', ';') }}
```

---

### Email Validation Macros

**File:** `macros/email_validation.sql`

| Macro | Purpose |
|-------|---------|
| `is_valid_email(email_field)` | Regex validation of email format |
| `email_filter_clause(email_field)` | Not null + not empty + valid format |
| `exclude_test_emails(email_field)` | Excludes test, example, noreply, retired addresses |
| `comprehensive_email_filter(email_field)` | Combines `email_filter_clause` + `exclude_test_emails` |

```sql
-- Full email validation
WHERE {{ comprehensive_email_filter('email') }}

-- Just format check
WHERE {{ is_valid_email('email') }}
```

---

### Common Filters

**File:** `macros/common_filters.sql`

| Macro | Purpose |
|-------|---------|
| `filter_code_contributions_non_bot(table_alias)` | Excludes bot contributions from code activity data |
| `exclude_individual_account(account)` | Filters out individual/no-account Salesforce records |
| `is_organization_domain(domain)` | Checks that an email domain is not a consumer provider (gmail, yahoo, etc.) |

```sql
-- Filter to human code contributions only
WHERE {{ filter_code_contributions_non_bot('c') }}

-- Exclude individual Salesforce accounts
WHERE {{ exclude_individual_account('account_id') }}
```

---

### Formatting and Cleanup Macros

**File:** `macros/format_helpers.sql`

| Macro | Purpose |
|-------|---------|
| `format_country(country)` | Normalizes messy country names to canonical values (handles US/USA/U.S.A., UK variants, etc.) |
| `clean_name_field(field)` | Cleans garbage/placeholder values from name fields (null, unknown, test, N/A, etc.) |
| `format_repository_url(repository_url)` | Lowercases and strips `.git` suffix |
| `email_to_domain(email)` | Extracts domain from an email address |
| `extract_repo_name(url_column)` | Extracts repository name from a git URL |
| `format_commit_url(repository_url, commit_id)` | Generates a clickable commit URL for GitHub, GitLab, Bitbucket, or kernel.org |
| `parse_github_username(field)` | Extracts a GitHub username from a URL or raw value |
| `parse_linkedin_username(field)` | Extracts a LinkedIn username from a URL or raw value |
| `is_apac_country(billing_country_column)` | Checks if a country is in the APAC region (China, HK, Taiwan, Macao) |

```sql
SELECT
    {{ format_country('raw_country') }} AS country,
    {{ clean_name_field('first_name') }} AS first_name,
    {{ email_to_domain('email') }} AS email_domain
FROM {{ ref('bronze_source') }}
```
