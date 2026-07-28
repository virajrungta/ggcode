# firmware/

ESP32 firmware for the GreenGenius pot. ESP-IDF v5.x, subtree-merged from
`virajrungta/gghard` with history preserved.

```bash
idf.py set-target esp32 && idf.py build flash monitor
```

## Layout

| File | Role |
|---|---|
| `main/gg_config.h` | Pinout and every tuning constant. **Verify against the schematic.** |
| `main/gg_sensors.c` | I²C drivers, soil calibration, wire-struct packing |
| `main/gg_pump.c` | Pump control and safety interlocks |
| `main/main.cpp` | BLE GATT server, telemetry task |
| `test/pack_probe.c` | Host-compilable struct layout probe |

## Status

Implemented: sensor layer with calibration, pump with full interlocks, BLE
GATT per `contracts/ble_gatt.md`, telemetry notify.

Not yet implemented (Phase 5+): `gg_net` (WiFi provisioning, MQTT, SNTP) and
OTA. The `claim_token` characteristic exists but is not yet populated —
that happens once the device can reach the backend.

## Before the boards arrive

`GG_SOIL_ADC_CHANNEL` **must** be an ADC1 channel (GPIO32–39 on the classic
ESP32). ADC2 is shared with the WiFi radio: `adc_oneshot_read` on an ADC2
channel returns `ESP_ERR_TIMEOUT` whenever WiFi is started, so the probe reads
correctly on the bench and then fails permanently once the pot joins a network
— the configuration the product actually ships in. After fabrication this is a
trace-cut fix, so check it now.

Also confirm the pump has its own supply rail. Switching an inductive load on
the 3.3V rail browns out the ESP32 mid-cycle, and a reset while the pump is
energised is the flood scenario `gg_pump_init` guards against.

## Testing without hardware

The struct layout — the part that silently corrupts data if it drifts — is
verified on the host:

```bash
cd backend && .venv/bin/python -m pytest tests/test_contract_firmware_struct.py
```

This compiles `test/pack_probe.c` and compares its bytes against
`contracts/vectors/telemetry.json`, the same vectors the backend codec and the
Flutter client decode.

## Safety interlocks

All in `gg_pump.c`, all enforced in firmware rather than trusted to the cloud,
because they must hold when the backend is unreachable, wrong, or compromised:

- 30 s hard cap per run, enforced by `esp_timer` (not a task delay — a starved
  or crashed task would leave the pump on)
- 2 min/hour and 10 min/day cumulative quotas
- 10 min minimum between runs
- refuses above 70% soil moisture
- refuses on an empty reservoir (running a diaphragm pump dry destroys it)
- GPIO driven low in `gg_pump_init` before anything else can fail

A *failed* soil reading deliberately does not block watering: a dead probe
should not mean the plant never gets water again, and the runtime caps still
bound the worst case.
