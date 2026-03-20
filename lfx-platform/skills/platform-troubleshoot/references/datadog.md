<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Datadog Reference

This file documents Datadog-specific patterns for troubleshooting LFX services.

---

## Key Datadog Tools

| Tool | When to use |
|---|---|
| `search_datadog_services` | Find a service by name, verify it exists in an environment |
| `search_datadog_monitors` | Check if any alerts are firing for the service or environment |
| `search_datadog_events` | Find deployment events, restarts, and cluster-level changes |
| `get_datadog_metric` | Pull specific metric values (error rate, latency, CPU, memory) |
| `search_datadog_logs` | Query logs for a specific service in a time window |
| `analyze_datadog_logs` | Let Datadog analyze a log query for patterns and anomalies |
| `search_datadog_spans` | Find distributed trace spans for a service or operation |
| `get_datadog_trace` | Get a specific trace by ID for deep inspection |
| `search_datadog_hosts` | Find hosts/nodes and their status |
| `get_datadog_metric_context` | Get surrounding metric context for a specific time |

---

## Service Naming

**TODO:** Document how LFX services are named in Datadog.

Questions to answer:
- Do service names in Datadog match Kubernetes deployment names exactly?
- Is there a prefix or suffix convention (e.g., `lfx-v2-committee-service`)?
- Are there separate entries for different components (API, worker, etc.)?

---

## Key Metrics to Check

**TODO:** Fill in the standard metrics for LFX services.

Suggested starting points:
- Error rate: `<!-- metric name -->`
- Request latency (p99): `<!-- metric name -->`
- Pod restart count: `<!-- metric name -->`
- CPU utilization: `<!-- metric name -->`
- Memory utilization: `<!-- metric name -->`

---

## Important Dashboards

**TODO:** Add links to key Datadog dashboards used by the platform team.

| Dashboard | URL | When to use |
|---|---|---|
| Cluster overview | <!-- URL --> | Node health, resource pressure |
| Service health | <!-- URL --> | Per-service error rates and latency |
| <!-- add others --> | | |

---

## Log Query Patterns

**TODO:** Document common log query patterns used in LFX.

Example patterns to document:
- Find all errors for a service in a time window
- Find pod restart events
- Find failed NATS message processing
- Find database connection errors
