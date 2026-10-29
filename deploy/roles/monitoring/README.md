# monitoring

Installs the configured server-monitoring stack on hosts in the
`[monitoring]` group and plumbs the instance hosts into it.

## Supported stacks

Set `server_monitoring` in the inventory:

| Value | Behaviour |
| ----- | --------- |
| `munin` | Munin master + per-node agent (default) |
| `prometheus` | Prometheus server + node + postgres exporters |
| `grafana` | Grafana server (typically paired with Prometheus) |
| `grafana/prometheus` | Combined stack installed in one pass |

Multi-stack selection is handled by splitting on `/`; see
`tasks/main.yml`.

## Responsibilities

- Install the chosen server stack on `[monitoring]`.
- Install Munin node and / or exporters (`node_exporter`,
  `postgres_exporter`) on every host that reports metrics.
- Deploy pre-built Grafana dashboards under `files/*.json` when the
  Grafana server play runs.
- Honour the existing operator configuration — custom dashboards and
  scrape configs are not overwritten on re-run.

## Tags

- `monitoring`
- `tomcat-munin-monitoring`
- `prometheus-connect`

## CLI integration

- `dhis2-monitor status | targets | exporters | dashboards |
  endpoints` — read-only inspection.
- `dhis2-monitor install | enable | disable` — delegate to the
  monitoring tag.
- `dhis2-monitor alerts | test-alert | silence | unsilence` —
  Alertmanager HTTP API v2 is used as a fallback when `amtool`
  is not installed; silences always include creator, reason, and
  expiry (section 57.12).
- `dhis2-monitor retention | storage` — report retention policy and
  on-disk growth.

## No-regression notes

- The CLI reflects what is actually configured; it does not assume
  Grafana / Prometheus (section 21).
- Alert testing does not disclose credentials (section 57.12).
- Monitoring updates preserve unrelated targets.
