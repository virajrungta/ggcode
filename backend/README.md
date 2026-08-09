# GreenGenius Backend

FastAPI service that ingests sensor telemetry from GreenGenius pots, stores it
as time-series data, assesses plant health against species-specific care
profiles, and issues watering commands.

---

## The pipeline, end to end

```
   ESP32 pot                     broker            backend              app
   ─────────                     ──────            ───────              ───

1. sample sensors every 60s
   soil / temp / humidity
        │
        ├── batch 12 samples ──▶ gg/v1/{id}/telemetry
        │                             │
        │                             ▼
        │                       ingest worker
        │                       ├─ validate + clamp
        │                       ├─ clock-skew guard
        │                       └─ COPY ──▶ readings (hypertable)
        │                                        │
        │                                        ▼
        │                             continuous aggregates
        │                             readings_1h / readings_1d
        │                                        │
        │                                        ▼
        │                                   FastAPI  ◀── GET /v1/pots/{id}/readings
        │                                   care engine ◀── GET .../health
        │
        └◀── gg/v1/{id}/cmd ◀── publish ◀── POST /v1/pots/{id}/water
             (expires_at, id)                   ▲
                  │                             │
                  └── ack ──▶ gg/v1/{id}/cmd/ack
```

Every arrow is a contract in [`../contracts/`](../contracts/).

---

## 1. A reading is born

`gg_sensors_read()` on the pot samples four ADC channels (median of 9, because
the pump throws outliers) and the DHT22. Each field carries a validity flag —
a failed I²C read must never be indistinguishable from a real `0.0`.

The pot batches 12 samples (or 5 minutes, whichever first) and publishes to
`gg/v1/{device_id}/telemetry` at QoS 1.

**Why batched:** at 60s intervals unbatched, a 10k-pot fleet is 10k publishes
per minute for no benefit.

## 2. Ingest

[`app/workers/ingest.py`](app/workers/ingest.py) subscribes to
`gg/v1/+/telemetry` and does four things before anything touches the database:

| Guard | Why |
|---|---|
| **device_id match** | A payload claiming a different `device_id` than its topic is dropped. The broker ACL should prevent it; this is defence in depth. |
| **Clock-skew** | Samples more than 24h future or 30d past are rejected. A pot whose SNTP failed would otherwise write 1970 timestamps into the hypertable and wreck every chart and rollup built over it. |
| **Plausibility clamp** | Out-of-range values become `null` and set a fault flag. A shorted ADC reading −3000 °C would otherwise flatten every temperature chart forever. |
| **Batch insert** | One transaction per batch, not per sample. |

Rows land in `readings`, a **TimescaleDB hypertable** partitioned on `time`.

**Why a hypertable:** a 90-day window at 60s sampling is ~130k rows per device.
Chunked storage plus compression after 7 days makes that queryable; a plain
table would not stay fast.

## 3. Aggregation

Migration `0002_timescale` creates two **continuous aggregates**:

- `readings_1h` — hourly averages plus soil min/max
- `readings_1d` — daily, built from the hourly rollup

The chart endpoint reads these, never the raw table. Raw data is retained 30
days; the aggregates keep the long tail.

The Timescale migration is guarded on the SQL dialect, so it is a no-op on
SQLite — local dev runs the same migration chain. It also degrades gracefully
if `timescaledb` is unavailable (plain RDS): the table stays ordinary and the
app keeps working, just without rollups.

## 4. Health assessment

[`app/services/care_engine.py`](app/services/care_engine.py) compares a reading
to a **care profile**, resolved most-specific-first:

```
species profile  →  genus default  →  global default
```

Every assessment reports which tier it used. "We know this plant wants 40–60%
soil moisture" and "we are guessing" must not look identical in the UI — the
app renders a banner when confidence is `default`.

Each parameter has a `Band`: an acceptable range with a comfortable core
inside it, producing `good` / `warning` / `bad`.

**A score of `None` is not a score of 0.** A pot with a dead sensor is not a
pot at 0% health, and showing either number would be a lie the user acts on.

> This replaced an earlier version that applied fixed 20/80 moisture
> thresholds to every plant and read Trefle's annual *precipitation* figure as
> a proxy for soil moisture. Those are different physical quantities — a cactus
> and a fern were judged identically.

## 5. Watering

`POST /v1/pots/{id}/water` checks duration cap, rate limit, and current soil
moisture, then writes a `commands` row and publishes to `gg/v1/{id}/cmd`.

**The backend's checks are a UX nicety. The firmware's are the real ones.**
`gg_pump.c` enforces a hardware-timer runtime cap, hourly/daily quotas, a
minimum interval, wet-soil refusal, and an empty-reservoir refusal — because
those must hold when the backend is unreachable, wrong, or compromised.

Every command carries `expires_at` and a unique `id`. With
`clean_session=false`, a pot offline for six hours receives its entire queued
backlog on reconnect; without expiry, "water for 5s" issued this morning fires
tonight, and QoS 1 redelivery fires it more than once. The firmware enforces
expiry and dedupes the last 16 ids.

Acks return on `gg/v1/{id}/cmd/ack` and update the `commands` row.

---

## Data model

```
users          firebase_uid ─ the app authenticates with Firebase; everything
                              else lives here
devices        one physical pot; holds the argon2 hash of its MQTT secret and
               a single-use claim code
pots           a user's plant. binds a device to a species
plant_species  care_profile as JSONB — requirements are heterogeneous and the
               shape will change as we learn what predicts plant health
readings       hypertable. no surrogate key: partitioned on time, and a serial
               id would add an index as large as the table
commands       queued → sent → acked | rejected | expired | failed
care_events    watering log, fed by pump_stopped events
alerts         reservoir empty, sensor fault, safety interlock tripped
```

## Authentication

Firebase issues ID tokens; the backend verifies them locally against Google's
JWKS with a cached key set — no Admin SDK, no per-request round trip.

The audience check is not optional: without it, a token from *any* Firebase
project would authenticate here.

Ownership is enforced by a single dependency, [`owned_pot`](app/api/v1/deps.py),
which every pot-scoped route depends on. Centralising it means a new route
cannot forget the `user_id` predicate without also forgetting the pot. It
returns **404, not 403**, for someone else's pot — a 403 confirms the id exists.

## Device claiming

1. Pot generates a claim code at boot, exposed over an encrypted BLE
   characteristic
2. App reads it during provisioning and `POST /v1/devices/claim`
3. Backend binds device → user, mints a per-device MQTT secret, returns it
   **once**, and stores only the argon2 hash

Per-device secrets, never a fleet-wide password: one extracted flash image
would otherwise compromise every pot ever shipped.

---

## Running it

```bash
cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
cp .env.example .env
.venv/bin/python scripts/checkpoint.py     # seeds a pot with 48h of history
GG_AUTH_MODE=dev .venv/bin/uvicorn app.main:app --host 0.0.0.0
```

Browse http://localhost:8000/docs.

`GG_AUTH_MODE=dev` trusts an `X-Dev-User` header instead of verifying tokens,
so you can `curl` without minting one. It is **rejected at startup** under
`GG_ENV=production`, along with `GG_SIMULATE`, plaintext MQTT, wildcard CORS,
and SQLite. Misconfiguration fails at boot rather than at the first request.

Full stack including Timescale, EMQX and MinIO:

```bash
cd infra && docker compose up -d
```

## Tests

```bash
cd backend && .venv/bin/python -m pytest -q     # 149 tests
```

Worth knowing what a few of them protect:

- **`test_contract_firmware_struct.py`** compiles the firmware's C struct on
  the host and checks its bytes against `contracts/vectors/telemetry.json`.
  A padding or endianness drift between firmware and backend does not crash —
  it produces plausible-looking wrong readings, which is far worse.
- **`test_migrations.py`** runs `alembic check`. `app.main` calls `create_all`
  on SQLite for convenience, so a model change works in dev and only explodes
  on the first Postgres deploy. This fails in CI instead.
- **`test_api_pots.py::TestOwnershipIsolation`** — six tests confirming user B
  gets 404 on user A's pot, readings, health, and pump.
- **`test_auth.py`** covers expiry, wrong audience, wrong issuer, unknown key
  id, a signature from a different key, and a hand-assembled `alg:none` token.

## Layout

```
app/
├── api/v1/       routes + pydantic schemas (source of truth for OpenAPI)
├── core/         config with production guards, Firebase auth
├── db/           SQLAlchemy 2.0 models, session
├── services/     plant_id, care_engine, telemetry_codec, mqtt
└── workers/      ingest (MQTT → Timescale), simulator
alembic/          migrations; 0002 is the Timescale layer
scripts/          checkpoint.py seeds a demoable dataset
```

`contracts/openapi.yaml` is **generated**, not hand-written — the Pydantic
models are the source of truth. Regenerate with
`python -m app.export_openapi`; CI fails if it is stale.
