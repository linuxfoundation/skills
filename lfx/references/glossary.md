<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# LFX Glossary

A plain-language reference for terms you'll encounter when working on LFX.

## Platform Terms

| Term | What It Is | Why It Matters |
|------|-----------|----------------|
| **Goa** | A Go framework that defines API endpoints using a design DSL. You describe what your API accepts and returns, and Goa generates the boilerplate code. | When adding a new field or endpoint, you edit the Goa "design" files and run `make apigen` to regenerate the server code. |
| **NATS** | A messaging system that lets services communicate. When one service saves data, it sends a message via NATS so other services can react (e.g., update search indexes, sync permissions). | If you add a new data type, it needs NATS messages so search and permissions stay in sync. |
| **OpenFGA (FGA)** | The permissions system. Controls who can view, edit, or delete each resource. Uses "tuples" (relationships like "user X is an editor of project Y"). | Every new resource needs FGA rules, otherwise nobody can access it — or everybody can. |
| **Heimdall** | An authorization gateway that sits in front of every API request. Checks if the caller has permission before the request reaches the service. | API routes need Heimdall rules in the Helm chart, or requests get rejected. |
| **OpenSearch** | A search and analytics engine (similar to Elasticsearch). Stores indexed copies of data for fast querying, filtering, and full-text search. | The query service reads from OpenSearch, not directly from the Go services. New data needs an indexer to get into OpenSearch. |
| **KV (Key-Value store)** | NATS-based key-value storage used for caching and lightweight data that doesn't need a full database. | Some services use KV for quick lookups like configuration or temporary state. |
| **PrimeNG** | A UI component library for Angular. LFX wraps PrimeNG components with `lfx-` prefixed wrappers to enforce consistent styling. | When building UI, use `lfx-table`, `lfx-button`, etc. — not raw PrimeNG components directly. |
| **Express proxy** | A Node.js server layer in the Angular app that forwards API requests to upstream Go services. Handles auth, logging, and request transformation. | Frontend components don't call Go services directly — they go through the Express proxy. |

## Architecture Terms

| Term | PM Translation |
|------|---------------|
| **Three-file pattern** | Every backend endpoint needs three files: a service (talks to upstream), a controller (handles the request), and a route (defines the URL). Think of it as: plumbing, logic, and address. |
| **Upstream Go service** | The backend service that owns the data. For example, the committee service owns all committee data. The Angular app never talks to it directly — it goes through the Express proxy. |
| **Resource service** | A Go microservice that owns one type of data (committees, meetings, votes, etc.). Each has its own repo, database, and API. |
| **Shared types** | TypeScript interfaces in a shared package that both the frontend and backend use. Keeps data shapes consistent. When you add a field, it goes here first. |
| **Domain model** | The Go struct that defines what a data object looks like in the backend (its fields and types). This is the source of truth for the data shape. |
| **Goa design** | The API blueprint files that define endpoints, request/response types, and validation rules. Changes here + `make apigen` = updated API code. |
| **Signal (Angular)** | A reactive value in Angular. When it changes, any UI that uses it automatically updates. Think of it like a spreadsheet cell — change the value, and everything that references it recalculates. |

## Workflow Terms

| Term | When You See It |
|------|----------------|
| **Preflight** | A set of automated checks run before submitting a pull request — formatting, linting, building, and checking for protected files. Like a checklist before takeoff. |
| **Protected file** | A file that requires special approval to change (e.g., server configuration, build settings). Changes to these files will be flagged in the PR. |
| **Code owner** | A team member who must approve changes to certain files. Protected files always need code owner review. |
| **Feature branch** | A separate copy of the code where you make changes without affecting the main codebase. Named like `feat/LFXV2-123-add-bio-field`. |
| **Delegation plan** | The coordinator's breakdown of what needs to happen, in what order, and which skills will do each part. You approve this before any code is written. |
| **Auto-fix** | Preflight can automatically fix some issues (formatting, missing license headers) without you doing anything. It asks before committing these fixes. |
| **Signoff** | A line in each commit (`Signed-off-by: Name <email>`) required by Linux Foundation projects for legal compliance. |
