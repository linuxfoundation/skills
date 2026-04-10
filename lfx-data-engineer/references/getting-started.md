<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Getting Started with lf-dbt

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Python | 3.11+ with virtual environment |
| Snowflake access | Provisioned via `lfx-snowflake-terraform` (see `/lfx-snowflake-access` skill) |
| dbt | Installed via `pip install -r requirements.txt` |
| Environment variables | Configured in `.env` file (see `.env.sample`) |

## Initial Setup

```bash
# 1. Clone the repository
git clone https://github.com/linuxfoundation/lf-dbt.git
cd lf-dbt

# 2. Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment variables
cp .env.sample .env
# Edit .env with your Snowflake credentials

# 5. Install dbt packages
dbt deps

# 6. Verify your connection
dbt compile
```

## Snowflake Connection

The connection is configured in `profiles.yml` with the `dbt-snowflake` profile:

| Setting | Source |
|---------|--------|
| Account | `SNOWFLAKE_ACCOUNT` env var |
| User | `DBT_ENV_SECRET_USER` env var |
| Password | `DBT_ENV_SECRET_PASS` env var |
| Role | `DBT_ENV_ROLE` env var |
| Database | `DBT_ENV_DATABASE` env var |
| Warehouse | `DBT_ENV_WAREHOUSE` env var |
| Default schema | `DBT_DEFAULT_SCHEMA` env var |

For keypair authentication (required for CLI/programmatic access), see the
[lf-dbt README — SnowSQL Keypair Authentication Setup](https://github.com/linuxfoundation/lf-dbt/blob/main/README.md#snowsql-keypair-authentication-setup).

## Essential dbt Commands

```bash
# Install package dependencies
dbt deps

# Compile models without running (validates SQL)
dbt compile

# Build all models and run tests
dbt build

# Build excluding cloned production data (use after cloning)
dbt build --exclude tag:cloned_data

# Build excluding large Kafka tables
dbt build --exclude tag:kafka_crowd_dev

# Build a specific model and all its upstream dependencies
dbt build --select +model_name

# Build by layer
dbt build --select tag:bronze
dbt build --select tag:silver
dbt build --select tag:gold
dbt build --select tag:platinum

# Run tests only
dbt test

# Preview query results without materializing
dbt show --select model_name

# Inspect the compiled SQL for a model
dbt compile --select model_name
# Then check target/compiled/core_warehouse/models/...

# Generate and view documentation
dbt docs generate
dbt docs serve
```

## Cloning Production Data for Development

Some bronze tables (Kafka CDP, Salesforce) are too large to rebuild in dev.
Clone production data to your dev schema instead:

```bash
# Clone tables and create views from production (run weekly)
dbt run-operation clone_production_tables

# With custom retention if Time Travel is needed
dbt run-operation clone_production_tables --args '{retention_days: 7}'

# Then exclude cloned data from your builds
dbt build --exclude tag:cloned_data
```

This creates 179 objects across 19 schemas:

- 112 Bronze views across 17 schemas
- 21 Bronze cloned tables across 17 schemas
- 39 Silver Dim cloned tables
- 7 Silver Fact cloned tables

Cloned tables use 0-day retention by default (no Time Travel history) to
optimize storage costs.

## Makefile Targets

The project includes shortcuts for building specific data domains:

| Command | What it builds |
|---------|---------------|
| `make edx` | EdX course and enrollment data |
| `make easycla` | EasyCLA signature data |
| `make bevy` | Bevy chapter and event data |
| `make events` | Platform event registration data |
| `make ti` | Training Institute data |
| `make webinars` | Webinar attendance data |
| `make individual_memberships` | Individual membership data |
| `make docs` | Generate dbt documentation |

### Linting

```bash
# Lint a specific file
sqlfluff lint path/to/file.sql

# Auto-fix formatting issues
sqlfluff fix path/to/file.sql

# Lint a specific file via Makefile
make lint-fix file=path/to/file.sql

# Lint all staged files (before commit)
make lint-staged-files

# Auto-fix all staged files
make fix-lint-staged-files
```

## Schema Organization

Each layer maps to specific Snowflake schemas. In production, the schema name
is used directly. In dev, it is prefixed with your default schema
(e.g., `your_schema_bronze_fivetran_platform`).

| Layer | Schema Pattern | Example |
|-------|---------------|---------|
| Bronze | `bronze_*` (per source) | `bronze_fivetran_platform`, `bronze_salesforce` |
| Silver Dim | `silver_dim` | `silver_dim` |
| Silver Fact | `silver_fact` | `silver_fact` |
| Gold | `gold_*` (per domain) | `gold_reporting`, `gold_fact` |
| Platinum | `platinum*` (per product) | `platinum`, `platinum_organization_dashboard` |

## Project Structure

```text
lf-dbt/
├── dbt_project.yml          # Main project configuration
├── profiles.yml             # Snowflake connection config
├── packages.yml             # dbt package dependencies
├── .sqlfluff                # SQL linting rules
├── Makefile                 # Build shortcuts
├── macros/                  # Reusable SQL fragments
├── models/
│   ├── bronze/              # Source-aligned raw data
│   │   ├── fivetran_platform/
│   │   ├── fivetran_salesforce/
│   │   ├── kafka_crowd_dev/
│   │   └── ...
│   ├── silver/              # Business logic layer
│   │   ├── dim/             # Dimensions
│   │   │   └── helper_models/
│   │   └── fact/            # Facts
│   │       └── helper_models/
│   ├── gold/                # Aggregated metrics
│   │   ├── fact/
│   │   ├── reporting/
│   │   └── ...
│   ├── platinum/            # Pre-computed reports
│   │   ├── individual_dashboard/
│   │   ├── organization_dashboard/
│   │   ├── lfx_one/
│   │   └── ...
│   └── semantic/            # Semantic layer definitions
├── data/                    # Seed data
├── tests/                   # Custom data tests
└── snapshots/               # dbt snapshots
```

## Git Workflow

All commits must be signed and include DCO signoff:

```bash
git commit -S --signoff -m "Add new bronze model for event registrations"
```

Branch naming follows the convention:

- `feature/{JIRA_TICKET}-{short-description}`
- `bug/{JIRA_TICKET}-{short-description}`

Example: `feature/DL-123-add-event-registrations-model`
