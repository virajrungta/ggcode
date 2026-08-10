# Hosting plan — $0 prototype

Goal: the app works when you open it, with no laptop running `uvicorn`, and
nothing on a credit card.

Researched Feb 2026. Free tiers move; re-check before relying on this.

---

## Why free is hard, and the change that makes it easy

Every free tier sleeps:

| Platform | Free tier | Sleeps? |
|---|---|---|
| Render | 750 hrs/mo, Postgres included, no card | after 15 min, ~1 min cold start |
| Koyeb | 512 MB / 0.1 vCPU | after 1 hr, **cannot be disabled** |
| Fly.io | trial only in 2026 | n/a |
| Railway | none ($5/mo minimum) | n/a |
| Oracle Cloud | 4 vCPU / 24 GB ARM, forever | **no** — but signup is famously painful |

Sleeping is fatal to **one** part of the current design: the MQTT ingest
worker holds a long-lived subscription, and a sleeping subscriber misses
telemetry entirely. QoS 1 only helps when a subscriber exists.

**So drop MQTT for the prototype.** Have the pot `POST` telemetry over HTTPS
instead. Then sleeping stops mattering — the POST itself wakes the service.

### Commands ride back in the response

The obvious objection: MQTT gave us instant downlink for "water now". HTTP is
request/response, so the server cannot push.

It does not need to. **The telemetry POST returns any pending commands.**

```
POST /v1/ingest/telemetry
  { "device_id": "...", "samples": [ ... ] }

200 OK
  { "accepted": 12,
    "commands": [ {"id": "...", "op": "pump",
                   "args": {"duration_s": 5}, "expires_at": 1770000000} ] }
```

No polling, no second connection, no broker. Worst-case latency for a
watering command is one telemetry interval.

That interval is a knob: 60s in production, and the firmware can drop to ~10s
for a few minutes after a BLE session, so tapping "Water now" while stood next
to the pot feels immediate. The interlocks and `expires_at` handling are
unchanged — the transport moved, the safety rules did not.

### What this costs

| Lost | Matters? |
|---|---|
| Instant downlink | No — bounded by the telemetry interval, tunable |
| Last-will (offline detection) | Mildly — infer offline from "no POST in 3 intervals" instead |
| Broker fan-out to many subscribers | Not at one pot |
| ~1 min cold start after idle | The app feels slow to open occasionally |

All of it is recoverable later: `contracts/telemetry.md` and the MQTT worker
stay in the repo, and switching back is a firmware flag plus redeploying the
worker.

---

## The free stack

```
  ESP32 ──HTTPS POST──▶ Render free web service ──▶ Neon Postgres (free)
              ◀── pending commands in response
                              ▲
  iPhone ────HTTPS───────────┘
```

| Piece | Service | Free tier |
|---|---|---|
| API | Render web service | 750 hrs/mo, no card required |
| Database | Neon Postgres | 0.5 GB, scale-to-zero |
| Auth | Firebase Auth | 50k MAU |
| **Total** | | **$0** |

Render's own Postgres is an alternative to Neon and keeps everything on one
platform; Neon's free tier is more generous on retention.

**Timescale is out.** Migration `0002_timescale` already checks
`pg_available_extensions` and skips the hypertable, compression and
aggregates when it is missing, leaving `readings` an ordinary indexed table.
One pot at 60s sampling is ~43k rows/month — plain Postgres does not notice.

---

## The real blocker is still auth

**The backend cannot go public as it stands.** `GG_AUTH_MODE=dev` trusts an
`X-Dev-User` header, so a public URL with it enabled is an open database.
`Settings._guard_production` refuses to boot that way, which is the point.

Firebase Auth is already written and tested server-side — 15 tests covering
expiry, wrong audience, wrong issuer, unknown key id, foreign signatures and
`alg:none`. Only the client half is missing, and it needs two files **from
your Firebase console** that I cannot fetch:

- `google-services.json` → `app/android/app/`
- `GoogleService-Info.plist` → `app/ios/Runner/`

Project `greengenius-b9d6f` already exists from the old Expo app.

### Device auth is separate

The pot has no Firebase account, so `/v1/ingest/telemetry` authenticates with
the per-device secret already issued at claim time and stored argon2-hashed in
`devices.mqtt_secret_hash`. Same secret, different transport — sent as a
bearer token over TLS instead of an MQTT password.

---

## Sequence

1. **Firebase Auth in the app** — sign-in screen, token on requests. *Blocks
   deployment; needs your two config files.*
2. **HTTP ingest endpoint** — `POST /v1/ingest/telemetry`, device-secret auth,
   pending commands in the response. Reuses the existing validation and
   clock-skew guards.
3. **Firmware HTTP mode** — swap `gg_net`'s MQTT publish for an HTTPS POST
   behind a compile flag, so MQTT stays available.
4. **Neon project** — point `GG_DATABASE_URL` at it, `alembic upgrade head`.
5. **Deploy to Render** — existing Dockerfile, secrets in the dashboard.
6. **Point app and pot at the URL** — no more LAN IP, so no rebuild when the
   router changes its mind.

Steps 2 and 3 are the real work; the rest is configuration.

## Things that will bite

- **Never deploy with dev auth**, not even briefly.
- **Cold starts.** First request after 15 min idle takes ~1 min. The pot's
  POST will time out and retry — the firmware must treat that as normal, not
  as failure.
- **Free Postgres is 0.5 GB.** Years away at one pot, but set retention before
  it matters.
- **Render sleeps on idle, not on a schedule.** A pot posting every 60s keeps
  it awake continuously, which may consume the 750 hrs/mo faster than
  expected. If it runs out, lengthen the interval or move to Oracle Cloud.
