# Backlog — known problems and hardcoded values

Running list. Add to it as things are found; delete entries when fixed.

Hardware findings live in [GGPCB4_NOTES.md](GGPCB4_NOTES.md); deployment in
[HOSTING_PLAN.md](HOSTING_PLAN.md).

---

## Blocking

### The pot cannot register itself
`/v1/ingest/bootstrap` now issues a pot its telemetry secret, but deliberately
does not create the `devices` row — an endpoint that minted devices on demand
would let anyone squat an unused device id before the real pot ever booted.

Nothing creates that row on a bench. `scripts/register_device.py` stands in,
and the pot logs a pointer to it when bootstrap fails.

**Fix:** a provisioning step that writes device ids and bootstrap tokens when
boards are flashed. Not an open endpoint.

---

## Hardcoded values to remove

| Where | Value | Should be |
|---|---|---|
| `gg_config.h` | `GG_API_BASE = http://MacBook-Air.local:8000` | configured at provisioning; the deployed https:// URL |
| `gg_config.h` | `GG_WLVL_EMPTY_RAW = 600` | measured, once a compatible sensor exists |
| `gg_config.h` | `GG_BRINGUP_MODE = 1` (2s sampling) | 0 before shipping; production is 60s |
| `core/providers.dart` | `GG_DEV_USER` default `dev-user` | removed once Firebase auth is enforced |
| `care_engine.py` | 3 species + 7 genus profiles | curated dataset, ~200 common houseplants |

---

## Known gaps

**Water level sensor is incompatible.** DFRobot SEN0204 is 5–24V digital; J4
is a 3.3V analog input, and its output at 5V would put 5V on GPIO34, which is
not 5V tolerant. `GG_WLVL_SENSOR_FITTED = 0`. See GGPCB4 notes.

**LDR not populated**, so light is reported absent rather than 0%. Correct
behaviour, but the app shows a permanently empty Light tile.

**Soil calibration never completed** — blocked on JST XH connectors. Loose
DuPont wires drop contact, and capturing a dropout as the air reference would
write a permanently wrong value to NVS.

**Sensors read as faults.** soil1 raw=0 (probe disconnected), DHT read fails —
both correctly reported as null rather than 0.0, so `readings` rows from the
real pot are all-null with flags=0x3C. Expected until the JST connectors land.

**Events have no HTTP uplink.** MQTT had a `event` topic; HTTP ingest has
`/telemetry`, `/ack` and `/bootstrap` and no equivalent. `gg_net_publish_event`
logs locally and returns OK, so a local watering never reaches the care log.

**Offline detection is server-side only.** MQTT's last-will marked a pot
offline the moment the broker noticed. With HTTP the backend sets `online` on
each POST and nothing clears it, so a dead pot reads as online forever. Needs a
`last_seen_at` staleness sweep.

**Plant.id is wired but unreachable from the UI.** `/v1/pots/{id}/identify`
works; nothing calls it. The Identify quick action is a stub.

**No OTA.** `esp_https_ota` is unconfigured despite two OTA partitions. Every
firmware change needs USB. Should exist before hardware leaves the bench.

**The backend runs on this Mac.** A launchd agent starts it at login, so it
survives reboots, but the phone only reaches it on the home Wi-Fi. `render.yaml`
deploys the same service publicly; it needs a Neon database and a Render
account, both of which are the user's to create.

**Free-account iOS signing expires after 7 days.** The app stops launching and
must be reinstalled; the symptom looks like a crash.

**BLE plugin races its own disconnect.** `flutter_esp_ble_prov` runs
`createESPDevice` on every call, which scans by name and connects — and a
peripheral stops advertising while connected. The network scan is best-effort
because of this. A retry made it worse by opening more connections.

---

## Process notes

**Check the device before debugging the app.** Three rounds went into
app-side BLE symptoms while the board's serial log read `net=3,
WIFI_CONNECTED` — provisioning had already succeeded and the pot had stopped
advertising, so every retry hunted something that no longer existed. Reading
the device state first would have shown it immediately.

**Do not reset the board mid-flow.** Reading the claim code regenerates it,
which invalidated a code the user was actively typing.

**Install from `build/ios/Release-iphoneos/`, not `build/ios/iphoneos/`.** The
latter is a stale copy from whichever build ran last, and installing it
shipped a debug binary three times while reporting success. Debug builds
cannot launch without a host attached, which looked like a crash.

**Keep the repo out of iCloud.** `~/Desktop` is synced; it was evicting
`.git/objects` entries and stamping files with attributes that make `codesign`
refuse. Now at `~/Developer/ggcode`.
