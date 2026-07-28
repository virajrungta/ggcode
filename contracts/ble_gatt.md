# GreenGenius BLE GATT Contract

**Version:** 1
**Status:** authoritative — firmware (`firmware/components/gg_ble`) and app (`app/lib/core/ble`) must both match this file.

## Device identity

- Advertised name: `GG-<last 6 of device_id>` (e.g. `GG-A31F0C`)
- Manufacturer data: company ID `0xFFFF` (test range) + 1 byte protocol version + 6 bytes device_id
- Appearance: `0x0000`

> The advertised name is per-device, not the literal string `Green Genius`. With more than one pot in a room, identical names make the pot unpickable in the app's scan list.

## UUIDs

A single 128-bit service. The previous firmware used 16-bit `ABCD`/`1234`; those live in the Bluetooth SIG reserved range and must not be used by custom services.

| Element | UUID |
|---|---|
| Service | `67670000-9622-433e-b3ab-bd248af9434c` |
| `device_info` | `67670001-9622-433e-b3ab-bd248af9434c` |
| `live_telemetry` | `67670002-9622-433e-b3ab-bd248af9434c` |
| `claim_token` | `67670003-9622-433e-b3ab-bd248af9434c` |
| `calibration` | `67670004-9622-433e-b3ab-bd248af9434c` |
| `command` | `67670005-9622-433e-b3ab-bd248af9434c` |
| `provisioning_status` | `67670006-9622-433e-b3ab-bd248af9434c` |

## Characteristics

### `device_info` — READ
UTF-8 JSON, ≤ 180 bytes:
```json
{"device_id":"a31f0c8e","fw":"1.0.0","hw":"ggpcb-r1","model":"GG-POT-1","prov":false}
```
`prov` indicates whether WiFi credentials are already stored. The app uses it to decide between the provisioning flow and the claim flow.

### `live_telemetry` — READ, NOTIFY, encrypted
15-byte packed little-endian struct. Notifies at 1 Hz while a client is subscribed, otherwise the device stays in its 60 s sampling cycle.

```c
typedef struct __attribute__((packed)) {
    uint32_t uptime_s;       // 0..2^32
    int16_t  temp_c_x100;    // 21.53 C  -> 2153   ; INT16_MIN = fault
    uint16_t rh_x100;        // 47.20 %  -> 4720   ; UINT16_MAX = fault
    uint16_t soil_pct_x100;  // calibrated 0..10000; UINT16_MAX = fault
    uint32_t lux_x10;        // 1234.5 lx -> 12345 ; UINT32_MAX = fault
    uint8_t  flags;
} gg_telemetry_t;            // sizeof == 15
```

Flags:
| Bit | Meaning |
|---|---|
| 0 | `PUMP_ON` |
| 1 | `RESERVOIR_LOW` |
| 2 | `SENSOR_FAULT` (at least one field carries its sentinel) |
| 3 | `UNCALIBRATED` — soil values are raw-derived and not trustworthy |
| 4 | `WIFI_CONNECTED` |
| 5 | `MQTT_CONNECTED` |
| 6–7 | reserved, must be 0 |

Fixed-point rather than float: identical decoding in C, Python, and Dart with no IEEE-754 edge cases, and it fits the 23-byte default ATT MTU with no negotiation.

Sentinels rather than a separate validity mask: a failed I²C read must never be indistinguishable from a real 0.

### `claim_token` — READ, encrypted
```json
{"device_id":"a31f0c8e","claim_code":"K7M2-P9QX","expires_at":1753660800}
```
Rotates on every successful claim and every reboot. 15-minute TTL. The app POSTs this to `/v1/devices/claim`.

### `calibration` — READ / WRITE, encrypted
```json
{"soil_air_raw":2810,"soil_water_raw":1180,"calibrated_at":1753660800}
```
Written by the app at the end of the two-step calibration flow, persisted to NVS. Reads return current values; `calibrated_at: 0` means never calibrated.

### `command` — WRITE, encrypted
Local override path, used when the device is offline or not yet provisioned.
```json
{"id":"c8f2","op":"pump","args":{"duration_s":5}}
```
Firmware applies the same safety interlocks as for cloud commands — BLE proximity is not authorization to bypass them.

Ops: `pump`, `identify_blink`, `factory_reset`, `reboot`.

### `provisioning_status` — NOTIFY
Emitted during WiFi provisioning:
```json
{"state":"connecting","detail":"","rssi":-52}
```
States: `idle` → `connecting` → `connected` → `cloud_ok`, or `failed` with `detail` in {`bad_password`, `ap_not_found`, `dhcp_timeout`, `mqtt_auth_failed`}.

Distinguishing these matters: "wrong WiFi password" and "router assigned no address" produce completely different support outcomes, and a single `failed` state makes both look like broken hardware.

## Security

- Pairing: bonding + MITM + Secure Connections, passkey display (`BLE_HS_IO_DISPLAY_ONLY`).
- The passkey must be **per-device, derived from the device secret at manufacture**, not the hardcoded `123456` currently in `main.cpp`. A fleet-wide static passkey means any bonded attacker can impersonate any pot.
- All characteristics except `device_info` require an encrypted link.
- WiFi credentials are **never** carried by a characteristic in this table. They go through ESP-IDF's `wifi_provisioning` manager with `scheme_ble` + Security2 (SRP6a), which runs its own service alongside this one.

## Connection parameters

| Phase | Interval | Latency | Timeout |
|---|---|---|---|
| Provisioning / live view | 15–30 ms | 0 | 4 s |
| Idle connected | 200–400 ms | 4 | 6 s |

Request the fast interval only while a live view or provisioning flow is actually on screen; holding 15 ms continuously is a meaningful battery cost on the phone side.
