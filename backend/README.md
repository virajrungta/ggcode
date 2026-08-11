# GreenGenius Backend

FastAPI service that ingests sensor telemetry from GreenGenius pots, stores it
as time-series data, assesses plant health against species-specific care
profiles, and issues watering commands.

---

## The pipeline, end to end

```
   ESP32 pot                                      backend              app
   ─────────                                      ───────              ───

1. sample sensors every 60s
   soil / temp / humidity
        │
        ├── batch 12 samples ──▶ POST /v1/ingest/telemetry
        │                             │      (Bearer: device secret)
        │                             ▼
        │                       ingest endpoint
        │                       ├─ validate + clamp
        │                       ├─ clock-skew guard
        │                       └─ insert ──▶ readings (hypertable)
        │                                        │
        │                                        ▼
        │                             continuous aggregates
        │                             readings_1h / readings_1d
        │                                        │
        │                                        ▼
        │                                   FastAPI  ◀── GET /v1/pots/{id}/readings
        │                                   care engine ◀── GET .../health
        │
        └◀── commands in the same response ◀── POST /v1/pots/{id}/water
             (id, op, args, expires_at)              queues a command
                  │
                  └── POST /v1/ingest/ack ──▶ command marked acked
```

**Why HTTP and not MQTT.** MQTT needs a broker plus a subscriber that is
always connected. Every free hosting tier sleeps after ~15 minutes idle, and a
sleeping subscriber loses telemetry outright — there is nothing holding the
subscription. A POST wakes the service instead, so idling costs latency
(a cold start on the next reading) rather than data.

The command downlink is what MQTT usually justifies, and it rides in the
telemetry response: no second connection, no polling, no broker. Worst case a
watering command waits one telemetry interval.

Every arrow is a contract in [`../contracts/`](../contracts/).

---

## 1. A reading is born

`gg_sensors_read()` on the pot samples four ADC channels (median of 9, because
the pump throws outliers) and the DHT22. Each field carries a validity flag —
a failed I²C read must never be indistinguishable from a real `0.0`.

The pot batches 12 samples (or 5 minutes, whichever first) and POSTs them to
`/v1/ingest/telemetry` with its device secret as a bearer token.

**Why batched:** at 60s intervals unbatched, a 10k-pot fleet is 10k publishes
per minute for no benefit.

## 2. Ingest

[`app/api/v1/ingest.py`](app/api/v1/ingest.py) receives the batch and does
four things before anything touches the database. The validation is shared
with the MQTT worker in [`app/workers/ingest.py`](app/workers/ingest.py), which
is retained for a future broker deployment, so the two cannot drift apart:

| Guard | Why |
|---|---|
| **Device auth** | The bearer secret is verified against an argon2 hash before anything is read. Unknown device and wrong secret return the same 401, so the response cannot enumerate device ids. |
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
moisture, then writes a `commands` row in state `queued`. The pot collects it
on its next telemetry POST — so the app is queuing work, not reaching the pot.

**The backend's checks are a UX nicety. The firmware's are the real ones.**
`gg_pump.c` enforces a hardware-timer runtime cap, hourly/daily quotas, a
minimum interval, wet-soil refusal, and an empty-reservoir refusal — because
those must hold when the backend is unreachable, wrong, or compromised.

Every command carries `expires_at` and a unique `id`. A pot offline for six
hours collects everything still queued the moment it comes back; without
expiry, "water for 5s" issued this morning fires tonight. The firmware
enforces expiry itself and dedupes the last 16 ids.

**Delivery is at-most-once.** The endpoint marks a command `sent` as it hands
it out, so a response lost in transit drops the command rather than retrying
it. That is the right trade for a pump: at-least-once would mean a pot that
watered and lost power before acking waters again on its next POST. A missed
watering is recoverable and the user can tap again; a double dose into a pot
is not.

Acks go to `POST /v1/ingest/ack` and update the `commands` row. They are
best-effort — a lost ack leaves the command `sent`, which is visible in the
database rather than silently forgotten.

---

## Data model

```
users          firebase_uid ─ the app authenticates with Firebase; everything
                              else lives here
devices        one physical pot; holds the argon2 hash of its telemetry secret and
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

Two separate secrets, because they answer different questions.

**`claim_code`** — proves to the *backend* that a user is physically near the
pot. The app reads it over the encrypted BLE provisioning link, or the user
types it off the label. Single use: `POST /v1/devices/claim` consumes it and
binds the device to the account.

**`bootstrap_token`** — proves to the *backend* that a caller is the pot.
Same value, different column, and never consumed. It has to be a separate
column precisely because claiming destroys `claim_code`: a pot that
authenticated with that value could never re-authenticate once its owner
claimed it, which is a device permanently unable to report.

```
pot boots ──▶ POST /v1/ingest/bootstrap {device_id, token}
                     │
                     ├─ 401 if the token is unknown or belongs to another device
                     └─ 200 ──▶ fresh secret, argon2-hashed server side,
                                stored in the pot's NVS
```

Bootstrap mints a new secret every call. That is deliberate: it makes the pot
self-healing. If its stored secret is ever invalidated it gets a 401, drops the
secret and bootstraps again, instead of going silent until someone reflashes
it. The cost is that only the newest secret works.

Bootstrap does **not** create the `devices` row. An endpoint that minted
devices on demand would let anyone register an unused device id and squat it
before the real pot booted. Registration is a provisioning step; on a bench,
[`scripts/register_device.py`](scripts/register_device.py) stands in.

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
