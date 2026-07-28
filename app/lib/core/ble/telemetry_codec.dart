/// Decoder for the 15-byte BLE telemetry struct.
///
/// Authoritative spec: `contracts/ble_gatt.md`
/// Golden vectors:     `contracts/vectors/telemetry.json`
///
/// The Python backend has a mirror of this in
/// `backend/app/services/telemetry_codec.py`. Both suites decode the same
/// vector file, so a wire-format change that lands on only one side fails both
/// builds rather than silently corrupting readings on one platform.
library;

import 'dart:typed_data';

/// Sentinels marking a failed sensor read. Distinct from a real zero — a dead
/// I2C bus must never be indistinguishable from 0.0 °C.
const int kTempFault = -32768;
const int kRhFault = 0xFFFF;
const int kSoilFault = 0xFFFF;
const int kLuxFault = 0xFFFFFFFF;

const int kFlagPumpOn = 1 << 0;
const int kFlagReservoirLow = 1 << 1;
const int kFlagSensorFault = 1 << 2;
const int kFlagUncalibrated = 1 << 3;
const int kFlagWifiConnected = 1 << 4;
const int kFlagMqttConnected = 1 << 5;

const int kTelemetrySize = 15;

class Telemetry {
  const Telemetry({
    required this.uptimeSeconds,
    required this.temperatureC,
    required this.humidity,
    required this.soilPercent,
    required this.lux,
    required this.flags,
  });

  final int uptimeSeconds;

  /// Null when the sensor reported a fault.
  final double? temperatureC;
  final double? humidity;
  final double? soilPercent;
  final double? lux;

  final int flags;

  bool get pumpOn => flags & kFlagPumpOn != 0;
  bool get reservoirLow => flags & kFlagReservoirLow != 0;
  bool get sensorFault => flags & kFlagSensorFault != 0;

  /// Soil readings are not trustworthy until the air/water calibration has
  /// been completed. The UI must prompt rather than display a percentage.
  bool get uncalibrated => flags & kFlagUncalibrated != 0;

  bool get wifiConnected => flags & kFlagWifiConnected != 0;
  bool get mqttConnected => flags & kFlagMqttConnected != 0;

  /// Decodes a notification payload from the `live_telemetry` characteristic.
  ///
  /// Throws [FormatException] on a wrong-sized buffer rather than accepting a
  /// truncated read — a short frame means the contract is broken somewhere,
  /// and guessing at the missing bytes would surface fiction as sensor data.
  factory Telemetry.decode(List<int> raw) {
    if (raw.length != kTelemetrySize) {
      throw FormatException(
        'expected $kTelemetrySize bytes, got ${raw.length}',
      );
    }

    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final data = ByteData.sublistView(bytes);

    // Little-endian throughout, matching the ESP32's native layout.
    final uptime = data.getUint32(0, Endian.little);
    final tempRaw = data.getInt16(4, Endian.little);
    final rhRaw = data.getUint16(6, Endian.little);
    final soilRaw = data.getUint16(8, Endian.little);
    final luxRaw = data.getUint32(10, Endian.little);
    final flags = data.getUint8(14);

    return Telemetry(
      uptimeSeconds: uptime,
      temperatureC: tempRaw == kTempFault ? null : tempRaw / 100.0,
      humidity: rhRaw == kRhFault ? null : rhRaw / 100.0,
      soilPercent: soilRaw == kSoilFault ? null : soilRaw / 100.0,
      lux: luxRaw == kLuxFault ? null : luxRaw / 10.0,
      flags: flags,
    );
  }

  /// Inverse of [Telemetry.decode]. Used by tests and the BLE fake.
  Uint8List encode() {
    final data = ByteData(kTelemetrySize);
    data.setUint32(0, uptimeSeconds, Endian.little);
    data.setInt16(
      4,
      temperatureC == null ? kTempFault : (temperatureC! * 100).round(),
      Endian.little,
    );
    data.setUint16(
      6,
      humidity == null ? kRhFault : (humidity! * 100).round(),
      Endian.little,
    );
    data.setUint16(
      8,
      soilPercent == null ? kSoilFault : (soilPercent! * 100).round(),
      Endian.little,
    );
    data.setUint32(
      10,
      lux == null ? kLuxFault : (lux! * 10).round(),
      Endian.little,
    );
    data.setUint8(14, flags & 0xFF);
    return data.buffer.asUint8List();
  }

  @override
  String toString() =>
      'Telemetry(uptime: ${uptimeSeconds}s, temp: $temperatureC, '
      'rh: $humidity, soil: $soilPercent, lux: $lux, '
      'flags: 0x${flags.toRadixString(16).padLeft(2, '0')})';
}
