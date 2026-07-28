# infra/

Local development stack. `docker compose up` gives you Timescale, Redis, EMQX, MinIO, the API, and the ingest worker.

```bash
cd infra && docker compose up -d
docker compose logs -f api ingest
```

| Service | Where | Credentials |
|---|---|---|
| API | http://localhost:8000/docs | `GG_AUTH_MODE=dev` — no Firebase needed |
| Postgres/Timescale | `localhost:5432` | `gg` / `gg_dev_only` |
| EMQX dashboard | http://localhost:18083 | `admin` / `public` |
| MinIO console | http://localhost:9001 | `gg` / `gg_dev_only` |

## Two dev-only settings that must not reach production

**`EMQX_ALLOW_ANONYMOUS: "true"`** — any client may connect and publish to any topic. In production the broker must authenticate `username == device_id` against `devices.mqtt_secret_hash` and enforce an ACL restricting each device to its own `gg/v1/{device_id}/#` prefix. Without that ACL, one compromised pot can run the pump on every other pot in the fleet.

**`GG_AUTH_MODE: dev`** — the API trusts an `X-Dev-User` header instead of verifying Firebase ID tokens. It exists so you can `curl` the API without minting tokens. The setting is rejected at startup when `GG_ENV=production`.

Both are deliberately loud in the config rather than silently defaulted, so neither can be inherited by accident.

## No Docker?

The backend runs directly against SQLite with no other services:

```bash
cd backend && cp .env.example .env && ./scripts/dev.sh
```

Sensor history uses plain SQL that works on both engines; the Timescale-specific parts (hypertable, continuous aggregates, compression) are guarded in the migration and skipped on SQLite. Charts still work — they just read the raw table instead of a rollup, which is fine at development data volumes and wrong at production ones.

## Production notes

This compose file is not a production topology. Notably: MQTT is plaintext on 1883 (production is TLS on 8883 with per-device credentials), Postgres has no replica, MinIO is single-node, and there is no reverse proxy or rate limiting in front of the API.
