# GreenGenius Telemetry & Command Contract (MQTT)

**Version:** 1 — topic namespace `gg/v1/`
**Status:** authoritative for `firmware/components/gg_net` and `backend/app/workers/ingest.py`.

## Transport

- MQTT 3.1.1 over TLS, port 8883, server-cert verified against a pinned CA bundle in firmware.
- Client ID = `device_id`.
- Credentials: username `device_id`, password = per-device secret issued at claim time and stored in NVS.
  **Never a fleet-wide shared password** — one extracted flash image would otherwise compromise every pot ever shipped.
- Keepalive 60 s. Clean session `false` so QoS-1 downlinks survive a brief dropout.

## Topics

| Topic | Dir | QoS | Retained |
|---|---|---|---|
| `gg/v1/{device_id}/telemetry` | device → cloud | 1 | no |
| `gg/v1/{device_id}/status` | device → cloud | 1 | **yes** (also the LWT) |
| `gg/v1/{device_id}/event` | device → cloud | 1 | no |
| `gg/v1/{device_id}/cmd` | cloud → device | 1 | no |
| `gg/v1/{device_id}/cmd/ack` | device → cloud | 1 | no |

A device may only publish/subscribe under its own `device_id` prefix; the broker ACL enforces this. Without that ACL any authenticated pot could pump any other pot.

## Payloads

All payloads are JSON. (CBOR is a later optimisation; JSON keeps the first version debuggable with `mosquitto_sub`.)

### `telemetry`
Batched. Sensors are read every 60 s; the batch publishes every 5 min or when it reaches 12 samples.

```json
{
  "v": 1,
  "device_id": "a31f0c8e",
  "samples": [
    {
      "ts": 1753660800,
      "temp_c": 21.53,
      "rh": 47.2,
      "soil_pct": 38.4,
      "lux": 1234.5,
      "batt_mv": 4021,
      "flags": 16
    }
  ]
}
```

- `ts` is Unix seconds, **device clock synced by SNTP**. If SNTP has not completed, the device sends `"ts": null` and the ingest worker substitutes arrival time. Never let an unsynced device write 1970 timestamps into a hypertable — it wrecks every chart and every continuous aggregate.
- Any sensor field may be `null` for a fault; the row is still stored, with that column null.
- Batching matters: at 60 s intervals unbatched, a 10k fleet is 10k publishes/minute for no benefit.

### `status` (retained + LWT)
```json
{"online": true, "fw": "1.0.0", "ip": "192.168.1.42", "rssi": -52, "ts": 1753660800}
```
LWT payload is `{"online": false, "ts": null}`. Retained so the backend learns liveness on subscribe without waiting for a telemetry window.

### `event`
```json
{"v":1,"ts":1753660800,"kind":"pump_stopped","data":{"duration_s":5,"reason":"completed"}}
```
Kinds: `boot`, `pump_started`, `pump_stopped`, `reservoir_empty`, `sensor_fault`, `calibrated`, `ota_started`, `ota_done`, `ota_failed`, `safety_tripped`.

`pump_stopped.reason` ∈ {`completed`, `max_runtime`, `soil_wet`, `reservoir_empty`, `user_abort`, `watchdog`} — the audit trail for every safety interlock.

### `cmd`
```json
{"id":"7c2f9a","op":"pump","args":{"duration_s":5},"expires_at":1753660980}
```

**`expires_at` is mandatory and the device must enforce it.** With `clean_session=false`, a pot offline for six hours receives its whole queued backlog on reconnect. Without expiry, "water for 5 s" issued this morning fires tonight — six times in a row.

The device must also deduplicate by `id` (keep the last 16 seen in RAM); QoS 1 is *at least once*, so redelivery is normal, not exceptional.

Ops: `pump`, `set_schedule`, `calibrate`, `reboot`, `factory_reset`, `ota`.

### `cmd/ack`
```json
{"id":"7c2f9a","result":"ok","ts":1753660805,"error":null}
```
`result` ∈ {`ok`, `rejected`, `expired`, `failed`}. `error` carries the interlock name on rejection (e.g. `soil_already_wet`, `rate_limited`, `reservoir_empty`).

## Ingest rules (backend)

1. Reject payloads whose `device_id` ≠ the authenticated MQTT username.
2. Drop samples with `ts` more than 24 h in the future or 30 d in the past (clock-skew guard).
3. Clamp to physical plausibility before insert; out-of-range → null + `sensor_fault` counter:
   | Field | Accepted |
   |---|---|
   | `temp_c` | −40 … 85 |
   | `rh` | 0 … 100 |
   | `soil_pct` | 0 … 100 |
   | `lux` | 0 … 200000 |
   | `batt_mv` | 0 … 6000 |
4. Batch-insert via `COPY`/`execute_many` into the `readings` hypertable.
5. Update the Redis latest-cache (`gg:latest:{device_id}`, 15 min TTL) and fan out to WebSocket subscribers.
6. Update `devices.last_seen_at` at most once per minute per device — not on every sample.

## Rates and budget

| Item | Value |
|---|---|
| Sample interval | 60 s |
| Publish interval | 300 s (12 samples) |
| Payload size | ~1.1 KB/batch |
| Per device | ~320 KB/day, ~10 MB/month |
| Live view | 1 Hz, session-scoped only |

## Versioning

The topic carries `v1`. A breaking payload change means `gg/v2/`, with the ingest worker subscribing to both during migration. Devices in the field outlive any given backend deploy — assume a v1 pot will still be publishing years after v2 ships.
