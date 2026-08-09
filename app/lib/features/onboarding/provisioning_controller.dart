import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/ble/provisioning_service.dart';
import '../../core/providers.dart';

final provisioningServiceProvider = Provider((ref) => ProvisioningService());

final provisioningControllerProvider =
    StateNotifierProvider<ProvisioningController, ProvisioningState>((ref) {
  return ProvisioningController(
    ref.watch(provisioningServiceProvider),
    ref.watch(apiClientProvider),
    ref,
  );
});

/// Drives the pairing flow: scan → credentials → claim.
///
/// The claim step is what makes the pot appear in the app. Provisioning alone
/// only gets the device onto Wi-Fi; until `/v1/devices/claim` runs, the
/// backend has no idea whose pot it is.
class ProvisioningController extends StateNotifier<ProvisioningState> {
  ProvisioningController(this._ble, this._api, this._ref)
      : super(const ProvisioningState());

  final ProvisioningService _ble;
  final ApiClient _api;
  final Ref _ref;

  Future<void> scan() async {
    state = state.copyWith(
      step: ProvisioningStep.requestingPermissions,
      clearError: true,
    );

    if (!await _ble.ensurePermissions()) {
      state = state.copyWith(
        step: ProvisioningStep.failed,
        error: 'Bluetooth permission is required to find your pot.',
      );
      return;
    }

    state = state.copyWith(step: ProvisioningStep.scanning, devices: []);
    try {
      final devices = await _ble.scanForPots();
      if (devices.isEmpty) {
        state = state.copyWith(
          step: ProvisioningStep.failed,
          // Named causes rather than "no devices found": each has a different
          // fix, and a generic message sends people to support.
          error: 'No pots found. Check the pot is powered, within a few '
              'metres, and has not already been set up.',
        );
        return;
      }
      state = state.copyWith(
        step: ProvisioningStep.deviceFound,
        devices: devices,
        selectedDevice: devices.first,
      );
    } catch (e) {
      state = state.copyWith(
        step: ProvisioningStep.failed,
        error: 'Bluetooth scan failed: $e',
      );
    }
  }

  void selectDevice(String name) =>
      state = state.copyWith(selectedDevice: name);

  /// Asks the pot which networks *it* can see.
  ///
  /// Deliberately the pot's view, not the phone's: ESP32 is 2.4GHz only, and
  /// a pot behind a wall may not reach the AP the phone is using. Offering
  /// the phone's list would let someone pick a network the pot can never
  /// join, and the failure would look like broken hardware.
  Future<void> loadNetworks(String claimCode) async {
    final device = state.selectedDevice;
    if (device == null) return;

    state = state.copyWith(
      step: ProvisioningStep.scanningNetworks,
      clearError: true,
    );
    try {
      final networks = await _ble.scanNetworks(device, claimCode);
      state = state.copyWith(
        step: ProvisioningStep.deviceFound,
        networks: networks,
      );
    } catch (e) {
      state = state.copyWith(
        step: ProvisioningStep.failed,
        error: 'Could not read networks from the pot. '
            'Check the setup code is correct. ($e)',
      );
    }
  }

  Future<void> provisionAndClaim({
    required String claimCode,
    required String ssid,
    required String passphrase,
    String? potName,
  }) async {
    final device = state.selectedDevice;
    if (device == null) return;

    state = state.copyWith(
      step: ProvisioningStep.sendingCredentials,
      clearError: true,
    );

    try {
      final ok = await _ble.provision(
        deviceName: device,
        proofOfPossession: claimCode,
        ssid: ssid,
        passphrase: passphrase,
      );
      if (!ok) {
        state = state.copyWith(
          step: ProvisioningStep.failed,
          error: 'The pot could not join that network. '
              'Check the password, and that it is a 2.4GHz network.',
        );
        return;
      }
    } catch (e) {
      state = state.copyWith(
        step: ProvisioningStep.failed,
        error: 'Provisioning failed: $e',
      );
      return;
    }

    state = state.copyWith(step: ProvisioningStep.claiming);
    try {
      final result = await _api.claimDevice(claimCode, name: potName);
      _ref.invalidate(potsProvider);
      state = state.copyWith(
        step: ProvisioningStep.done,
        potId: result['pot_id'] as String?,
      );
    } on ApiException catch (e) {
      /* Wi-Fi succeeded but claiming did not. Saying so matters: the pot is
       * on the network and will keep trying, so this is recoverable by
       * retrying the claim alone rather than starting setup over. */
      state = state.copyWith(
        step: ProvisioningStep.failed,
        error: 'Your pot joined the network, but registering it failed: '
            '${e.message}',
      );
    }
  }

  void reset() => state = const ProvisioningState();
}
