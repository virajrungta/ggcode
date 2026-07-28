# contracts/

Wire formats shared by three codebases in three languages. If firmware, backend, and app disagree about a byte, this directory is what decides.

## What lives here

| File | Owner | Nature |
|---|---|---|
| `ble_gatt.md` | hand-written | UUIDs, characteristic table, packed telemetry struct |
| `telemetry.md` | hand-written | MQTT topics, payloads, ingest rules |
| `openapi.yaml` | **generated** from FastAPI | REST surface |

## Why REST is generated, not hand-written

FastAPI already derives a complete OpenAPI document from the Pydantic request/response models. Hand-maintaining a parallel `openapi.yaml` creates two sources of truth that drift within a sprint — and the drift is silent, because nothing validates one against the other.

So: **the Pydantic models are the source of truth for REST.** The spec is exported as a build artifact and committed so the Flutter client can be generated from it and so API diffs show up in review.

Regenerate after any route or model change:

```bash
cd backend && python -m app.export_openapi
```

CI runs the same command and fails if the working tree changes — a route edit that forgets the export cannot merge.

## Why BLE and MQTT are hand-written

Nothing owns them. The GATT table exists in C in the firmware and in Dart in the app, with no shared generator; the MQTT payloads exist in C and Python. In both cases the only thing keeping the two sides honest is this prose plus the round-trip tests:

- `backend/tests/test_contract_telemetry.py` — decodes golden byte-vectors against the struct spec
- `app/test/ble_codec_test.dart` — the same vectors, decoded in Dart

Both suites read the vectors from `vectors/telemetry.json`, so a struct change breaks both builds rather than silently corrupting readings on one platform.

## Changing a contract

1. Edit the contract file.
2. Update `vectors/` if the wire format moved.
3. Update all three implementations.
4. Bump the version — `v1` → `v2` in the MQTT topic namespace, or the protocol byte in BLE manufacturer data.

Devices in the field outlive backend deploys. A pot flashed with v1 will still be publishing long after v2 ships, so removing v1 support is a fleet-wide decision, not a cleanup task.
