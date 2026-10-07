# opti-api-gateway

The single entrance of OptiView. **It is configuration, not code**: a declarative NGINX proxy
with no state and no business rules (Annex F of the norm).

Part of the OptiView distributed system (team `opti`). Governance and documentation live in
[`opti-docs`](https://github.com/code-corhuila/opti-docs).

## What it does and what it does not

| Responsibility | Where |
|---|---|
| Route `/api/v1/<domain>/…` to the right service, `/api/v1/sagas` to the workflow | here, one file per domain in `nginx/routes/` |
| Refuse a protected request with **no** bearer credential (cheap filter) | here |
| Rate limit (general, and strict for sign-in) and CORS | here |
| Reuse or generate `X-Correlation-Id`, forward it, return it and log it | here |
| Answer **its own** errors with the common envelope (401, 404, 413, 429, 503) | here |
| **Validate** the token (signature, expiry, role) | **in each service**, never only here |
| Business rules, database, migrations | never here |

| Route | Service |
|---|---|
| `POST /api/v1/auth/login` (public) · `/api/v1/auth/**` · `/api/v1/users/**` | `auth-api` |
| `/api/v1/patients/**` | `customers-api` |
| `/api/v1/frames/**` · `/api/v1/reservations/**` | `products-api` |
| `/api/v1/work-orders/**` · `/api/v1/invoices/**` | `sales-api` |
| `/api/v1/sagas/**` | `workflow` |
| `GET /health` | the gateway itself |

## Its own errors

| Situation | Answer |
|---|---|
| Protected route without a bearer credential | `401 UNAUTHORIZED` |
| Route that does not exist | `404 NOT_FOUND` |
| Body larger than 1 MB | `413 VALIDATION_ERROR` |
| Rate limit exceeded | `429 TOO_MANY_REQUESTS` with `Retry-After` |
| The target service does not answer | `503 SERVICE_UNAVAILABLE` |

All with `{"error", "message", "traceId"}`; `traceId` is the `X-Correlation-Id`, so a complaint with
its reference leads straight to the log line. What a service answers passes untouched.

## Why it resolves names on every request

With a static `upstream` block NGINX resolves the services once, at start: a domain that is down
at that moment keeps the whole gateway from starting. Here every `location` uses a **variable** in
`proxy_pass` and the resolver is Docker's (`127.0.0.11`): if a domain falls, **its routes** answer
`503` and all the others keep working.

## CORS

Only the origin of the front (`FRONT_ORIGIN`). `Authorization`, `Content-Type`, `Idempotency-Key`
and `X-Correlation-Id` are allowed; `X-Correlation-Id` and `Location` are exposed so the browser
can read them. An unknown origin gets no `Access-Control-Allow-Origin`. Never `*`.

## Add a domain

1. Create `nginx/routes/<domain>.conf` copying another one: a variable in `proxy_pass`.
2. Run `tests/smoke.sh` (CI does it on every Pull Request).

## Run

The whole platform is started from `opti-infra`. Alone:

```bash
docker network create platform          # once
cp .env.example .env
docker compose --env-file .env -f deploy/compose.yml up -d --build
GATEWAY_URL=http://localhost:8000 FRONT_ORIGIN=http://localhost:3000 ./tests/smoke.sh
```

`SMOKE_UPSTREAMS_DOWN=true` adds the check that a dead service gives `503` while the gateway
stays healthy (what CI runs, since nothing is behind it there).

## Depends on

Only the names of the services on the `platform` network (`auth-api`, `customers-api`,
`products-api`, `sales-api`, `workflow`). It publishes the only port of the domains (`8000`).
