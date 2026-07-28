# GreenGenius — Full Implementation Plan

**Scope:** unify `gghard/` (ESP32 firmware) and `ggcode/` (FastAPI backend + Expo app) into one product; rebuild the frontend in Flutter with a glass UI; replace all mocked data paths with real ones.

**Architecture decisions (locked):**
- Transport: BLE for provisioning + offline live view; WiFi + MQTT for cloud telemetry.
- Backend: FastAPI + Postgres/TimescaleDB. Firebase Auth retained for identity only; Firestore retired.
- Sensors: capacitive soil moisture, temp/humidity (I²C), light (I²C lux), plus a **pump output** — so the system is actuating, not just sensing.

---

## 1. Where the project actually stands

An honest audit, because the plan below is mostly about closing these gaps.

| Layer | File | Reality |
|---|---|---|
| Firmware | `gghard/main/main.cpp` | BLE server advertising "Green Genius", one characteristic returning a hardcoded string. **Zero sensor code.** Uses 16-bit UUIDs `ABCD`/`1234` — those belong to the Bluetooth SIG's reserved range and must not be used by custom services. |
| Backend | `ggcode/backend/arduino_service.py` | `random.uniform()`. Every sensor reading the app has ever shown is fabricated. |
| Backend | `ggcode/backend/main.py` | No auth, no database, no device concept, `allow_origins=["*"]`. Stateless proxy to Plant.id/Trefle. |
| Backend | `ggcode/backend/analysis_service.py` | Hardcoded 20/80 moisture thresholds; the "ideal range" logic reads Trefle precipitation as a moisture proxy, which is not meaningful. |
| App | `mobile/src/components/BluetoothSetup.tsx` | `setTimeout` theatre. No BLE stack is installed — Expo Go cannot do BLE at all. |
| App | `mobile/src/utils/api.ts` | `BACKEND_URL` hardcoded to `http://10.0.0.243:8000`. Cleartext, LAN-only. |
| App | `mobile/src/screens/DashboardScreen.tsx` | Builds `newEnvStatus` as four hardcoded `'good'` entries, then string-matches backend issue text to downgrade them. |
| App | `mobile/src/firebase/config.ts` | Firebase web config committed. Not fatal (these are public identifiers by design) but Firestore rules become the *only* thing protecting user data — verify they exist. |

**The three layers have never exchanged a real byte.** Treat the existing code as a UX prototype that proved the screens, not as a foundation to extend.

### What is worth keeping
- The **design language** in `mobile/src/theme/index.ts` — the volt-green/near-black palette is good and ports directly to Flutter tokens.
- The **screen inventory and IA** — dashboard / analytics / community, pot list, camera identify, plant result. Reuse as the Flutter spec.
- `plant_id_client.py` — the Plant.id v3 call is correct and moves over nearly as-is.
- The Firebase **Auth** integration (not Firestore).

---

## 2. Target architecture

```
┌──────────────┐   BLE GATT (provisioning, live, calibration)   ┌──────────────┐
│              │◀──────────────────────────────────────────────▶│              │
│   ESP32-S3   │                                                │ Flutter app  │
│   + PCB      │                                                │ (iOS/Android)│
│              │   MQTT/TLS 8883                    HTTPS + WSS │              │
└──────┬───────┘                                                └──────┬───────┘
       │                                                               │
       │  gg/v1/{device_id}/telemetry ──▶                              │
       │  ◀── gg/v1/{device_id}/cmd                                    │
       ▼                                                               ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  Broker (EMQX)  →  ingest worker  →  FastAPI  ←  Firebase Auth (JWKS verify)│
│                                         │                                   │
│                          TimescaleDB (readings hypertable)                   │
│                          Postgres (users, devices, pots, species, commands)  │
│                          Redis (live cache, command queue, rate limits)      │
│                          S3/R2 (plant photos)                                │
│                                         │                                   │
│                          Plant.id v3 (identify + health assessment)          │
└────────────────────────────────────────────────────────────────────────────┘
```

**Why the phone is not in the data path:** with a pump on the board, the pot must be able to act on a schedule when nobody's phone is nearby. BLE-relay-only would mean watering stops when you leave the house.

### Monorepo layout

```
greengenius/
├── firmware/               # was gghard/
│   ├── main/
│   └── components/
│       ├── gg_sensors/     # driver abstraction + calibration
│       ├── gg_ble/         # GATT server, provisioning
│       ├── gg_net/         # WiFi, MQTT client, OTA
│       └── gg_control/     # pump scheduler + safety interlocks
├── backend/                # was ggcode/backend/
│   ├── app/
│   │   ├── api/v1/
│   │   ├── core/           # config, auth, deps
│   │   ├── db/             # models, migrations
│   │   ├── services/       # plant_id, care_engine, ingest
│   │   └── workers/
│   ├── alembic/
│   └── tests/
├── app/                    # NEW Flutter
├── contracts/              # ✱ single source of truth
│   ├── openapi.yaml
│   ├── telemetry.proto     # or the packed-struct spec
│   └── ble_gatt.md
├── infra/                  # docker-compose, terraform, broker config
└── docs/
```

`contracts/` matters more than it looks. Three codebases in three languages must agree on one wire format; without a checked-in spec they will silently drift.

---

## 3. Data contracts

### 3.1 BLE GATT

Generate real 128-bit UUIDs (`uuidgen`) — replace `ABCD`/`1234` immediately. Base: `6ge0xxxx-...` style, one service, distinct characteristic UUIDs.

| Characteristic | Props | Payload |
|---|---|---|
| `device_info` | READ | JSON: `{fw, hw, device_id, model}` |
| `live_telemetry` | NOTIFY, READ_ENC | 15-byte packed struct (below), 1 Hz while subscribed |
| `provisioning` | WRITE_ENC | delegated to ESP-IDF `wifi_provisioning` manager |
| `claim_token` | READ_ENC | one-time device claim code, rotates after use |
| `calibration` | R/W ENC | `{soil_air_raw, soil_water_raw}` |
| `command` | WRITE_ENC | `{op: "pump", duration_s: 5}` — local override path |

**Use ESP-IDF's `wifi_provisioning` manager with `scheme_ble` and Security2 (SRP6a)** rather than hand-rolling credential transfer over a custom characteristic. It handles the key exchange, is audited, and Espressif ships matching phone SDKs. Hand-rolled WiFi-password-over-BLE is the single easiest way to ship a serious vulnerability.

Telemetry struct (little-endian, fits the 23-byte default MTU with no negotiation):

```c
typedef struct __attribute__((packed)) {
    uint32_t uptime_s;
    int16_t  temp_c_x100;    // 21.53°C → 2153
    uint16_t rh_x100;
    uint16_t soil_pct_x100;  // calibrated, 0–10000
    uint32_t lux_x10;
    uint8_t  flags;          // bit0 pump_on, bit1 low_water, bit2 sensor_fault
} gg_telemetry_t;            // 15 bytes
```

Fixed-point, not float — deterministic across the C/Python/Dart boundary and half the bytes.

### 3.2 MQTT

TLS on 8883. Per-device credentials provisioned during claim; **do not ship one shared broker password in the firmware image** — one extracted flash dump would compromise the entire fleet.

| Topic | Dir | QoS | Payload |
|---|---|---|---|
| `gg/v1/{device_id}/telemetry` | ↑ | 1 | CBOR/JSON, batched up to 12 samples |
| `gg/v1/{device_id}/status` | ↑ | 1 | retained + LWT `{"online":false}` |
| `gg/v1/{device_id}/event` | ↑ | 1 | `pump_started`, `pump_stopped`, `reservoir_empty`, `sensor_fault` |
| `gg/v1/{device_id}/cmd` | ↓ | 1 | `{id, op, args, expires_at}` |
| `gg/v1/{device_id}/cmd/ack` | ↑ | 1 | `{id, result, error?}` |

Every command carries an `id` and an `expires_at`. Devices reconnecting after a 6-hour outage must **not** replay a queued watering command — expiry is the guard, and it belongs in the contract, not in firmware comments.

Sampling: read sensors every 60 s, publish batched every 5 min. Live view (WS or BLE subscribe) bumps to 1 Hz for the duration of the session only.

### 3.3 Database schema

```sql
users            (id uuid pk, firebase_uid text unique, email, created_at)
devices          (id text pk, hw_serial, model, fw_version, mqtt_secret_hash,
                  claim_code text, claimed_by uuid→users, claimed_at, last_seen_at)
pots             (id uuid pk, user_id→users, device_id→devices, name,
                  species_id→plant_species, photo_url, created_at)
plant_species    (id uuid pk, plant_id_ref, scientific_name, common_name,
                  care_profile jsonb, source, updated_at)
readings         (time timestamptz, device_id text, temp_c, rh, soil_pct,
                  lux, batt_mv, flags)              -- ← hypertable
commands         (id uuid pk, device_id, op, args jsonb, state, issued_by,
                  issued_at, expires_at, acked_at, result)
care_events      (id uuid pk, pot_id, kind, volume_ml, source, at)
alerts           (id uuid pk, pot_id, kind, severity, opened_at, resolved_at)
```

TimescaleDB specifics:
- `SELECT create_hypertable('readings', 'time', chunk_time_interval => INTERVAL '1 day')`
- Continuous aggregates `readings_1h` and `readings_1d` — the app's charts query these, never raw.
- Compression after 7 days, `segmentby => device_id`.
- Retention: raw 30 d, hourly 2 y, daily forever.

`care_profile` as JSONB rather than columns: care requirements are heterogeneous per species (some have light-hours, some have dormancy periods, some have pH) and the shape will change as you learn what actually predicts plant health.

### 3.4 REST API v1

Auth: `Authorization: Bearer <firebase_id_token>`, verified server-side against Google's JWKS with cached keys. Middleware resolves the token to a `users` row, auto-creating on first sight.

```
POST   /v1/devices/claim          {claim_code}  → binds device, returns mqtt creds
GET    /v1/pots
POST   /v1/pots                   {name, device_id?}
GET    /v1/pots/{id}
PATCH  /v1/pots/{id}
DELETE /v1/pots/{id}
GET    /v1/pots/{id}/latest       → last reading + derived status
GET    /v1/pots/{id}/readings?from&to&bucket=1h
POST   /v1/pots/{id}/identify     multipart image → species + confidence + alternates
GET    /v1/pots/{id}/health       → care-engine assessment
POST   /v1/pots/{id}/water        {duration_s|volume_ml} → enqueues command
GET    /v1/pots/{id}/events
POST   /v1/pots/{id}/schedule     {rules[]}
WS     /v1/stream?pot_id=         → live readings + command acks
POST   /v1/ingest/ble             phone relays BLE readings for offline devices
```

Note `identify` takes **multipart, not base64 JSON**. The current design inflates every photo 33% and forces the whole thing into memory on both ends.

---

## 4. Phased delivery

Each phase ends in something demonstrable. Estimates assume one developer working steadily; treat them as relative weights, not commitments.

### Phase 0 — Foundations (~3–5 days)
- Restructure into the monorepo above. Two repos exist today — `virajrungta/ggcode` (backend + Expo app) and `virajrungta/gghard` (firmware). Decide between:
  - **Merge into one repo** (recommended): `git subtree add --prefix=firmware <gghard-url> main` preserves gghard's history inside ggcode. One repo means the `contracts/` directory can be atomically updated across firmware, backend, and app in a single commit — which is the whole point of having it.
  - Keep them split and vendor `contracts/` as a submodule in both. More ceremony, and contract changes stop being atomic.
- Do the restructure as its own commit on a branch off `main` (both repos are currently clean and pushed, so this is low-risk).
- `infra/docker-compose.yml`: Postgres+Timescale, EMQX, Redis, MinIO.
- Keep secrets in env files. `.gitignore` already covers `.env*` and `backend/.env` has never been committed — that's correct as-is, no rotation needed.
- CI: lint + test for backend, `flutter analyze`, `idf.py build`.
- Write `contracts/` v0 before writing implementation code.

**Exit:** `docker compose up` gives a working local stack.

### Phase 1 — Firmware sensor layer (~1–2 weeks, gated on PCB arrival)
- `gg_sensors` component: I²C bus init, driver per sensor behind a common `gg_sensor_read(gg_reading_t*)` interface so a part substitution doesn't ripple.
- **Soil calibration**: capacitive probes vary 15–20% part-to-part and drift with temperature. Store `air_raw`/`water_raw` in NVS, expose via BLE calibration characteristic, and ship a two-step calibration flow in the app ("hold in air" → "submerge to line"). Uncalibrated raw ADC percentages will make the whole product feel broken.
- **ADC1 only.** ADC2 is unusable whenever WiFi is active on ESP32 — if the moisture probe is wired to an ADC2 pin, readings will fail exactly when the device is online. Check this against your schematic *now*, before the boards ship; it is a trace-cut fix afterward.
- Median-of-5 filtering, plausibility bounds, `sensor_fault` flag on out-of-range.
- Replace the dummy characteristic with `live_telemetry` notify.

**Exit:** nRF Connect shows real, calibrated, changing values.

### Phase 2 — Backend v1 (~1.5–2 weeks, parallel with Phase 1)
- SQLAlchemy 2.0 models + Alembic migrations for the schema above.
- Firebase JWKS auth dependency.
- Device claim flow.
- MQTT ingest worker: subscribe `gg/v1/+/telemetry`, validate, batch-insert to Timescale, update Redis latest-cache, fan out to WS subscribers.
- **Delete `arduino_service.py`.** Keep one clearly-labelled `SimulatedDevice` behind a `GG_SIMULATE=1` flag for development without hardware — the mistake was never simulation, it was simulation that looked like production.
- Port `plant_id_client.py`; switch `/identify` to multipart.

**Exit:** `mosquitto_pub` a fake telemetry frame → row lands in Timescale → `GET /v1/pots/{id}/latest` returns it.

### Phase 3 — Flutter foundation + design system (~2 weeks)
- Project scaffold, `go_router`, Riverpod, `dio` client generated from `contracts/openapi.yaml`, Firebase Auth, freezed models.
- Design system (section 5) with a widget-gallery screen.
- Login/signup ported from `LoginScreen.tsx`.

**Exit:** signed-in user sees an empty, beautiful dashboard.

### Phase 4 — BLE provisioning end-to-end (~1.5 weeks)
- `flutter_blue_plus` + `permission_handler`. iOS: `NSBluetoothAlwaysUsageDescription`; Android 12+: `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` and the neverForLocation flag.
- Onboarding flow: scan → pair (passkey) → WiFi scan list → credentials → wait for `provisioned` → read claim token → `POST /v1/devices/claim`.
- Rewrite `BluetoothSetup.tsx`'s fake states as real ones — the state machine it mocks (`scanning/found/connecting/success/error`) is the right one, it just needs real events behind it.

**Exit:** unbox → app → pot online in the cloud, no dev tools involved.

### Phase 5 — Live telemetry + charts (~1.5 weeks)
- WS live view, BLE fallback when the device is offline but nearby.
- `fl_chart` time-series over the continuous aggregates, range selector.
- Port `PlantRingDashboard`/`MetricCard`/`CircularProgress` to Flutter.

**Exit:** water the plant by hand, watch the moisture curve move in the app.

### Phase 6 — Plant ID + real care engine (~1.5 weeks)
- Camera + gallery capture → `/identify` → species assignment.
- **Replace `analysis_service.py` entirely.** Build a `care_profile` table with real per-species ranges (soil moisture %, lux hours/day, temp band, humidity band) seeded from a curated dataset for the top ~200 houseplants; fall back to a genus default, then a global default. Confidence-tag every assessment.
- Evaluate Plant.id's **health assessment** endpoint for disease detection from photos — it's a better fit than anything hand-rolled.
- ⚠️ **Trefle is unreliable as a dependency** — the project has been unmaintained/effectively shut down for a long stretch, and `trefle_client.py` will start failing silently (the code already swallows its errors). Verify it still responds before building on it; plan on the curated table as the primary source with Trefle as, at most, optional enrichment.

**Exit:** photograph a plant → correct species → thresholds that reflect that species.

### Phase 7 — Watering + automation (~1.5 weeks)
Safety is the whole job here. A stuck-on pump floods a room.

Firmware interlocks, all of them local and independent of the cloud:
- Hard max single run (e.g. 30 s), enforced by a hardware timer, not a delay loop.
- Max total runtime per rolling hour and per day.
- Minimum interval between runs.
- Pump refuses to start if soil is already above a wet threshold.
- Watchdog kills the pump on any task hang; pump off in the reset handler.
- Reservoir-empty detection (current sensing or float switch) → refuse and raise an event.

Then: manual water button, schedule rules, moisture-triggered auto-watering (opt-in, off by default), push notifications via FCM.

**Exit:** app-triggered watering works and every abuse case fails safe.

### Phase 8 — Analytics + community port (~1.5 weeks)
Port `AnalyticsScreen`, `CommunityScreen`, `PlantGroupScreen`, `CreateCommunityScreen` (~1,750 lines of RN) to Flutter against Postgres-backed endpoints. Migrate existing Firestore community docs with a one-shot script.

Consider deferring community entirely to post-v1 — it is a third of the remaining UI work and contributes nothing to the core "does my plant survive" loop.

### Phase 9 — Hardening (~2 weeks)
- OTA (`esp_https_ota`) with signed images and rollback. Ship this **before** any hardware leaves your desk; without it, every firmware bug is a physical recall.
- Secure boot + flash encryption decision (irreversible once burned — decide deliberately).
- Rate limits, per-user quotas on Plant.id calls (it's billed per identification).
- Load test ingest; integration tests; crash reporting; privacy policy + store listings.

---

## 5. Flutter app design

### Structure
```
lib/
├── main.dart
├── app/            router.dart, bootstrap.dart
├── design/         tokens.dart, glass.dart, widgets/
├── core/           api/, auth/, ble/, ws/, storage/, result.dart
└── features/
    ├── auth/  onboarding/  dashboard/  pot_detail/
    ├── identify/  analytics/  watering/  settings/
```
Feature-first, each with `data/ domain/ presentation/`. Riverpod for state, freezed for models, `dio` + `retrofit` from the OpenAPI spec.

### The glass look
Port the existing palette (`#050A07` bg, `#D4FF00` volt, `#2DE2E6`/`#F706CF` accents) as `tokens.dart`, then build glass on top:

- A `GlassSurface` widget: `BackdropFilter(ImageFilter.blur(sigmaX/Y: 20))` + `Colors.white.withOpacity(0.06)` fill + 1px `white.withOpacity(0.12)` top-left-biased border + a soft outer shadow.
- Depth needs something *behind* the glass to blur: an animated mesh-gradient background of 2–3 slow-drifting radial gradients in volt/cyan. Glass over flat black just looks grey.
- Accent glow via layered `BoxShadow` in the volt colour at low opacity — this is what sells "alive" on a plant product.
- Frosted bottom nav and modal sheets.

**Performance caveat, and it is a real one:** `BackdropFilter` is one of the most expensive things in Flutter. Each instance forces a saveLayer. Rules: never put one inside a scrolling list item; cap to ~3 blurred surfaces on screen; wrap in `RepaintBoundary`; drop `sigma` to ~10 on Android; and test on a genuinely low-end device early. If a glass card must repeat in a list, fake it with a static translucent gradient — visually near-identical, an order of magnitude cheaper.

Motion: `flutter_animate` for staggered entrances, hero transitions pot-card → detail, spring physics on the ring gauge.

---

## 6. Security checklist

- [x] API keys kept out of git — `.gitignore` covers `.env*`, `backend/.env` never committed. Verified.
- [ ] Custom 128-bit BLE UUIDs; drop `ABCD`/`1234`.
- [ ] Per-device MQTT credentials, never a fleet-wide shared secret.
- [ ] TLS everywhere; no cleartext `http://` in any build.
- [ ] `wifi_provisioning` Security2 rather than a custom credential characteristic.
- [ ] Firebase ID tokens verified server-side, every request.
- [ ] Ownership check on every pot/device route — the most likely IDOR in this design.
- [ ] CORS restricted to known origins (currently `["*"]`).
- [ ] Claim codes single-use and rate-limited.
- [ ] Signed OTA images with rollback.
- [ ] Firestore rules audited before migration, since data lives there today.

---

## 7. Principal risks

| Risk | Mitigation |
|---|---|
| **PCB bring-up surprises** — first-spin boards usually have at least one issue | Phases 0/2/3 are hardware-independent; keep `GG_SIMULATE=1` until boards are validated |
| **ADC2 + WiFi conflict** | Verify the moisture probe pin against the schematic *before* boards ship |
| **Pump flooding** | Layered local interlocks (Phase 7); never trust a cloud command alone |
| **Brownout when the pump kicks in** | Separate pump supply rail, adequate bulk capacitance, MOSFET + flyback diode; a 3.3V-rail pump will reset the ESP32 mid-cycle |
| **Trefle is effectively dead** | Curated care-profile table as primary source |
| **Plant.id per-call cost** | Cache by image hash, per-user quotas, client-side quality gate before upload |
| **Glass UI jank on low-end Android** | Budget blurred surfaces; profile on a real cheap device in Phase 3, not Phase 9 |
| **iOS BLE background limits** | Cloud path is primary; BLE is provisioning + foreground live view only |
| **Scope: community features** | Strong candidate to cut from v1 |

---

## 8. Recommended order of attack

1. **Verify the ADC2/WiFi pin question against your schematic.** The one item with a hard deadline attached to a physical object — after the boards ship it becomes a trace-cut fix.
2. Decide merge-vs-submodule for the two repos, then Phase 0 restructure + `contracts/` v0.
3. Then Phases 1 (firmware) and 2 (backend) in parallel, since they're independent until they meet at MQTT.

The critical path to a genuinely working product is **Phase 1 → 2 → 4 → 5**: real sensors, real ingest, real provisioning, real display. Everything else is enhancement on top of a loop that, once closed, is the actual product.
