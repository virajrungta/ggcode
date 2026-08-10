# Hosting plan — getting off "start the server first"

Goal: the app works when you open it, without a laptop running `uvicorn`.

Researched Feb 2026. Prices and free tiers move; re-check before committing.

---

## The constraint that rules most options out

**The pot publishes 24/7 and the ingest worker must hold an open MQTT
connection.** That single fact eliminates most free tiers:

| Platform | Free tier | Verdict |
|---|---|---|
| Render | 750 hrs/mo, **spins down after 15 min idle**, ~1 min cold start | ✗ A spun-down ingest worker drops the MQTT session. Telemetry published while it sleeps is gone — QoS 1 only helps if a subscriber exists. |
| Railway | No free tier. $5/mo hobby, includes $5 credit | ✓ |
| Fly.io | No free tier in 2026. Per-second billing, no seat fee | ✓ cheapest raw compute |

Anything that sleeps on idle is disqualified for the worker. A web-only API
could tolerate it; the ingest path cannot.

## Recommended stack

Three pieces, roughly **$5/month**:

```
  ESP32 ──mqtts:8883──▶ HiveMQ Cloud (free, 100 devices)
                              │
                              ▼
                    Fly.io: api + ingest      ~$5/mo
                              │
                              ▼
                    Neon Postgres (free, 0.5 GB)
```

**MQTT — HiveMQ Cloud free tier.** 100 device connections, TLS included. We
need two (pot + ingest worker). EMQX Serverless free is the alternative and
allows up to 1000 connections with a monthly quota; either is comfortable.
Self-hosting EMQX means running and securing another service for no benefit
at this scale.

**Compute — Fly.io.** Two processes from one image: `api` (uvicorn) and
`ingest` (the MQTT worker). Per-second billing, no seat fee, and it does not
sleep. Railway is the easier alternative — app and Postgres on one platform
for $5/mo — at slightly higher cost and less control.

**Database — Neon free tier.** 0.5 GB, scale-to-zero with a ~0.5s cold start
on first query after idle. Supabase is the alternative: always-on compute,
500 MB, but free projects **pause after 7 days idle** — irrelevant here since
the pot writes continuously.

### Drop TimescaleDB for now

Neon and Supabase are plain Postgres — no `timescaledb` extension.

That is already handled: migration `0002_timescale` checks
`pg_available_extensions` and skips the hypertable, compression and continuous
aggregates when unavailable, leaving `readings` an ordinary indexed table.

At one pot, 60s sampling is ~43k rows/month. Plain Postgres handles that
without noticing. Timescale earns its place at fleet scale, not now, and
`GET /v1/pots/{id}/readings` already aggregates in SQL either way.

Revisit when either is true: more than ~50 pots, or raw retention beyond a
few months.

---

## The actual blocker is authentication, not hosting

**The backend cannot be deployed publicly as it stands.** It runs with
`GG_AUTH_MODE=dev`, which trusts an `X-Dev-User` header — anyone who knows the
URL is any user they choose.

`Settings._guard_production` already refuses to boot with `GG_ENV=production`
and dev auth, so this cannot ship by accident. But it means **step one is
auth, not infrastructure.**

### Use the Firebase project that already exists

The backend's Firebase verification is written and tested — 15 tests covering
expiry, wrong audience, wrong issuer, unknown key id, foreign signatures, and
`alg:none`. The old Expo app already used project `greengenius-b9d6f`.

What is missing is only the client half:

1. Download `google-services.json` (Android) and `GoogleService-Info.plist`
   (iOS) from the Firebase console. **These come from your account — I cannot
   fetch them.**
2. Add `firebase_core` + `firebase_auth` to the Flutter app
3. Build a sign-in screen; attach the ID token via `ApiClient.setAuthToken`
4. Flip the deployed backend to `GG_AUTH_MODE=firebase`

Roughly a day's work, and it is the gate on everything else.

> Considered and rejected: moving the whole backend to Firebase (Firestore +
> Cloud Functions). Firestore bills per document write, which is a poor fit
> for 43k+ sensor rows a month, and it has no time-bucketed aggregation — the
> chart endpoint would have to read every row and reduce in memory. Firebase
> stays what it is good at: identity.

---

## Sequence

**1. Firebase Auth end-to-end** *(blocks everything; needs your config files)*
Sign-in screen, token attached to requests, backend switched to `firebase`.

**2. Managed Postgres**
Create a Neon project, point `GG_DATABASE_URL` at it, run `alembic upgrade
head`. The Timescale migration self-skips.

**3. MQTT broker**
HiveMQ Cloud instance; per-device credentials rather than one shared password.
Update `GG_MQTT_*` and the firmware's `GG_MQTT_URI` to `mqtts://…:8883`.

**4. Deploy**
`fly.toml` with two processes from the existing `Dockerfile`. Secrets via
`fly secrets set`, never committed.

**5. Point the app at it**
`--dart-define=GG_API_URL=https://greengenius.fly.dev`. No more LAN IP, so no
more rebuilds when the router changes its mind.

**6. Reflash firmware**
`GG_MQTT_URI` to the cloud broker with TLS. This is when `GG_MQTT_TLS=true`
starts being enforced — `Settings` rejects plaintext MQTT in production.

---

## Costs

| Item | Monthly |
|---|---|
| Fly.io — api + ingest | ~$5 |
| Neon Postgres | $0 (free tier) |
| HiveMQ Cloud | $0 (free tier) |
| **Total** | **~$5** |

Railway instead of Fly is also ~$5 and simpler to set up, with Postgres
included, at the cost of some control.

## Things that will bite

- **Do not deploy with dev auth**, even briefly. A public URL with an
  `X-Dev-User` header is an open database.
- **Per-device MQTT credentials, and a broker ACL** restricting each device to
  its own `gg/v1/{device_id}/#` prefix. Without the ACL, one compromised pot
  can run the pump on every other pot.
- **Neon's cold start** adds ~0.5s to the first request after idle. Fine for
  the app; the ingest worker keeps the connection warm anyway.
- **Free-tier storage is 0.5 GB.** At one pot that is years away, but the
  retention policy is worth setting before it matters.
