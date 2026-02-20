# Metrics API

## Overview

Metrics API is a FastAPI REST service for versioned KPI and user-segment queries.

## Features

- **Versioned queries**: `version` parameter
- **KPI**: single-day or date-range
- **User segments**: by segment type
- **Health check**: `/health`
- **Metadata**: versions and metric list

## Stack

- **FastAPI** — web framework
- **Trino** — query engine (Iceberg)
- **Python 3.11+**

## Quick start

### Install deps

```bash
cd services/metrics_api
pip install -r requirements.txt
```

### Env vars

```bash
export TRINO_HOST=localhost
export TRINO_PORT=8080
export TRINO_USER=admin
export TRINO_CATALOG=iceberg
export TRINO_SCHEMA=mart
```

Or use `.env` (see project root `.env.example`).

### Start

```bash
# Dev (reload)
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Prod
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Or: `make api-start`

### Test

```bash
curl http://localhost:8000/health
curl "http://localhost:8000/kpi?date=2026-01-15&version=v1"
curl "http://localhost:8000/user_segment?segment=high_value&version=v1"
```

## Endpoints

### Health

```http
GET /health
```

Response: `{"status": "healthy", "service": "metrics-api"}`

### KPI

**Single day**: `GET /kpi?date=2026-01-15&version=v1`

Params: `date` (required, YYYY-MM-DD), `version` (optional, default v1), `metrics` (optional, comma-separated).

**Date range**: `GET /kpi/range?start_date=...&end_date=...&version=v1`

### User segment

`GET /user_segment?segment=high_value&date=...&version=v1&limit=100`

Params: `segment` (required: high_value, medium_value, low_value, churn_risk, active, dormant), `date`, `version`, `limit` (default 100, max 10000).

### Metadata

- `GET /versions` — available versions
- `GET /metrics/list?version=v1` — metric list

## Config

| Var | Description | Default |
|-----|-------------|---------|
| TRINO_HOST | Trino host | localhost |
| TRINO_PORT | Trino port | 8080 |
| TRINO_USER | Trino user | admin |
| TRINO_CATALOG | Iceberg catalog | iceberg |
| TRINO_SCHEMA | Schema | mart |
| QUERY_TIMEOUT_SECONDS | Query timeout | 30 |
| CACHE_TTL_SECONDS | Cache TTL | 300 |

Default query timeout 30s; overrun returns 500.

**Cache (planned)**: TTL cache, key `{endpoint}_{date}_{version}`, TTL 5 min, Redis or in-memory.

## Errors

- **404**: No KPI for date/version → check data exists
- **400**: Unsupported version → use supported version
- **500**: Trino query failed → check Trino and tables

## Performance

- Filter on indexed fields (e.g. kpi_date)
- Use `limit`
- Prefer date-range over multiple single-day queries

**Cache (planned)**: Cache date-scoped KPI, key with date+version, TTL 5–10 min.

## Deploy

**Docker**: `docker build -t metrics-api:latest .` then `docker run -p 8000:8000 --env-file .env metrics-api:latest`

**K8s**: See `platform/k8s/`

## Monitoring

- Health: poll `/health`
- Metrics: API p95 < 300ms, query success rate, Trino latency
- Logs: request info, query details, errors

## Troubleshooting

**Trino connection**: Check env, test `trino --server localhost:8080`, check network.

**Empty results**: `SHOW TABLES FROM iceberg.mart`, `SELECT * FROM iceberg.mart.mart_kpis_daily_v1 LIMIT 10`, check date format.

**Performance**: Check Trino, table size, consider cache.

## References

- [FastAPI](https://fastapi.tiangolo.com/)
- [Trino](https://trino.io/docs/)
- [Project 2 README](../../README.md)
