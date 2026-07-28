import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greengenius/core/ble/telemetry_codec.dart';

/// Decodes the same golden vectors as the Python suite
/// (`backend/tests/test_contract_telemetry.py`) and the C probe
/// (`backend/tests/test_contract_firmware_struct.py`).
///
/// Three implementations, one vector file. A wire-format change applied to
/// only one of them fails here.
void main() {
  final vectorsFile = File('../contracts/vectors/telemetry.json');

  late List<dynamic> vectors;

  setUpAll(() {
    expect(
      vectorsFile.existsSync(),
      isTrue,
      reason: 'missing ${vectorsFile.path} — run from the app/ directory',
    );
    final doc = jsonDecode(vectorsFile.readAsStringSync());
    expect(doc['size_bytes'], kTelemetrySize);
    vectors = doc['vectors'] as List<dynamic>;
  });

  bytesFromHex(String hex) => List<int>.generate(
        hex.length ~/ 2,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      );

  group('golden vectors', () {
    test('every vector decodes to the expected fields', () {
      for (final vec in vectors) {
        final name = vec['name'] as String;
        final expected = vec['decoded'] as Map<String, dynamic>;
        final t = Telemetry.decode(bytesFromHex(vec['hex'] as String));

        expect(t.uptimeSeconds, expected['uptime_s'], reason: '$name uptime');
        expect(t.flags, expected['flags'], reason: '$name flags');

        if (expected['temp_c_x100'] == kTempFault) {
          expect(t.temperatureC, isNull, reason: '$name temp fault');
        } else {
          expect(t.temperatureC,
              closeTo((expected['temp_c_x100'] as int) / 100.0, 1e-9),
              reason: '$name temp');
        }

        if (expected['rh_x100'] == kRhFault) {
          expect(t.humidity, isNull, reason: '$name rh fault');
        } else {
          expect(t.humidity, closeTo((expected['rh_x100'] as int) / 100.0, 1e-9),
              reason: '$name rh');
        }

        if (expected['soil_pct_x100'] == kSoilFault) {
          expect(t.soilPercent, isNull, reason: '$name soil fault');
        } else {
          expect(t.soilPercent,
              closeTo((expected['soil_pct_x100'] as int) / 100.0, 1e-9),
              reason: '$name soil');
        }

        if (expected['lux_x10'] == kLuxFault) {
          expect(t.lux, isNull, reason: '$name lux fault');
        } else {
          expect(t.lux, closeTo((expected['lux_x10'] as int) / 10.0, 1e-9),
              reason: '$name lux');
        }
      }
    });

    test('encode/decode round-trips byte-for-byte', () {
      for (final vec in vectors) {
        final raw = bytesFromHex(vec['hex'] as String);
        expect(Telemetry.decode(raw).encode(), equals(raw),
            reason: 'round trip failed for ${vec['name']}');
      }
    });
  });

  group('fault sentinels', () {
    test('all-fault frame decodes every field to null', () {
      const t = Telemetry(
        uptimeSeconds: 1,
        temperatureC: null,
        humidity: null,
        soilPercent: null,
        lux: null,
        flags: kFlagSensorFault,
      );
      final decoded = Telemetry.decode(t.encode());
      expect(decoded.temperatureC, isNull);
      expect(decoded.humidity, isNull);
      expect(decoded.soilPercent, isNull);
      expect(decoded.lux, isNull);
      expect(decoded.sensorFault, isTrue);
    });

    test('real zero survives — the distinction sentinels exist for', () {
      const t = Telemetry(
        uptimeSeconds: 0,
        temperatureC: 0,
        humidity: 0,
        soilPercent: 0,
        lux: 0,
        flags: 0,
      );
      final decoded = Telemetry.decode(t.encode());
      expect(decoded.temperatureC, 0.0);
      expect(decoded.humidity, 0.0);
      expect(decoded.soilPercent, 0.0);
      expect(decoded.lux, 0.0);
      expect(decoded.sensorFault, isFalse);
    });

    test('negative temperature decodes correctly', () {
      final freezing =
          vectors.firstWhere((v) => v['name'] == 'freezing');
      final t = Telemetry.decode(bytesFromHex(freezing['hex'] as String));
      expect(t.temperatureC, closeTo(-12.5, 1e-9));
    });
  });

  group('flags', () {
    test('are decoded independently', () {
      const t = Telemetry(
        uptimeSeconds: 0,
        temperatureC: 20,
        humidity: 50,
        soilPercent: 40,
        lux: 100,
        flags: kFlagPumpOn | kFlagUncalibrated | kFlagWifiConnected,
      );
      final d = Telemetry.decode(t.encode());
      expect(d.pumpOn, isTrue);
      expect(d.uncalibrated, isTrue);
      expect(d.wifiConnected, isTrue);
      expect(d.reservoirLow, isFalse);
      expect(d.mqttConnected, isFalse);
    });
  });

  group('malformed input', () {
    for (final size in [0, 1, 14, 16, 32]) {
      test('$size-byte buffer is rejected', () {
        expect(
          () => Telemetry.decode(List<int>.filled(size, 0)),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });
}
