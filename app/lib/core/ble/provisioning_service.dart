import 'dart:io';

import 'package:flutter_esp_ble_prov/flutter_esp_ble_prov.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wi-Fi provisioning over BLE.
///
/// Talks to the firmware's `wifi_provisioning` manager (see
/// `firmware/main/gg_net.c`). The plugin wraps Espressif's own iOS/Android
/// SDKs, so the protocomm handshake — protobuf framing, X25519 key exchange,
/// AES-CTR, proof-of-possession — is handled by the same code Espressif ships
/// for their own apps.
///
/// The proof-of-possession is the device's claim code, which the firmware
/// generates at boot and prints to serial. The user reads it off the pot.
class ProvisioningService {
  ProvisioningService({FlutterEspBleProv? plugin})
      : _plugin = plugin ?? FlutterEspBleProv();

  final FlutterEspBleProv _plugin;

  /// Firmware advertises as `GG-<last 6 of device id>`, so this prefix
  /// isolates our pots from every other BLE device in range.
  static const devicePrefix = 'GG-';

  /// Requests the permissions BLE needs, which differ sharply by platform.
  ///
  /// Android 12+ split Bluetooth into `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`;
  /// below that, scanning required *location* permission, which is the single
  /// most common reason a scan silently returns nothing. iOS needs neither at
  /// this layer — the Info.plist usage strings cover it.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // locationWhenInUse is only required on Android < 12. Treat it as
    // advisory so a modern device is not blocked by a permission it does
    // not actually need.
    return statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;
  }

  /// Scans for GreenGenius pots in provisioning mode.
  ///
  /// Only unprovisioned devices appear: once credentials are stored the
  /// firmware boots into its telemetry GATT server instead, and the
  /// provisioning service is no longer advertised.
  Future<List<String>> scanForPots({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final all = await _plugin.scanBleDevices(devicePrefix).timeout(
          timeout,
          onTimeout: () => <String>[],
        );
    return all.where((n) => n.startsWith(devicePrefix)).toList();
  }

  /// Lists networks the pot can see — not the phone.
  ///
  /// This distinction matters: a pot sitting behind a wall may not reach the
  /// 5GHz AP the phone is happily using, and ESP32 is 2.4GHz only. Showing
  /// the phone's list would let the user pick a network the pot can never
  /// join, and the failure would look like a broken device.
  Future<List<String>> scanNetworks(String deviceName, String proofOfPossession) {
    return _withDevicePresent(
      deviceName,
      () => _plugin.scanWifiNetworks(deviceName, proofOfPossession),
    );
  }

  /// Re-scans before an operation that looks the device up by name.
  ///
  /// The plugin resolves the device on every call, and a BLE peripheral stops
  /// advertising while a central is connected to it. So the scan that found
  /// the pot moments ago does not guarantee the next call can find it, and
  /// the failure surfaces as "no bluetooth device found with given prefix" —
  /// which reads like the pot vanished rather than a stale lookup.
  ///
  /// One retry after a fresh scan covers the common case without turning a
  /// genuinely absent device into a long hang.
  Future<T> _withDevicePresent<T>(
    String deviceName,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (_) {
      await _plugin.scanBleDevices(devicePrefix).timeout(
            const Duration(seconds: 5),
            onTimeout: () => <String>[],
          );
      // Give the stack a moment to settle after the scan before retrying.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return action();
    }
  }

  /// Sends credentials. Returns true when the pot reports it joined.
  Future<bool> provision({
    required String deviceName,
    required String proofOfPossession,
    required String ssid,
    required String passphrase,
  }) async {
    final ok = await _withDevicePresent(
      deviceName,
      () => _plugin.provisionWifi(
        deviceName,
        proofOfPossession,
        ssid,
        passphrase,
      ),
    );
    return ok ?? false;
  }
}

/// Where a provisioning attempt got to, so the UI can say something specific.
enum ProvisioningStep {
  idle,
  requestingPermissions,
  scanning,
  deviceFound,
  connecting,
  scanningNetworks,
  sendingCredentials,
  claiming,
  done,
  failed,
}

class ProvisioningState {
  const ProvisioningState({
    this.step = ProvisioningStep.idle,
    this.devices = const [],
    this.networks = const [],
    this.selectedDevice,
    this.error,
    this.potId,
  });

  final ProvisioningStep step;
  final List<String> devices;
  final List<String> networks;
  final String? selectedDevice;
  final String? error;
  final String? potId;

  bool get isBusy =>
      step != ProvisioningStep.idle &&
      step != ProvisioningStep.done &&
      step != ProvisioningStep.failed &&
      step != ProvisioningStep.deviceFound;

  ProvisioningState copyWith({
    ProvisioningStep? step,
    List<String>? devices,
    List<String>? networks,
    String? selectedDevice,
    String? error,
    String? potId,
    bool clearError = false,
  }) {
    return ProvisioningState(
      step: step ?? this.step,
      devices: devices ?? this.devices,
      networks: networks ?? this.networks,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      error: clearError ? null : (error ?? this.error),
      potId: potId ?? this.potId,
    );
  }
}
