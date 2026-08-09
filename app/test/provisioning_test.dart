import 'package:flutter_test/flutter_test.dart';
import 'package:greengenius/core/ble/provisioning_service.dart';

/// Covers the provisioning state machine.
///
/// The BLE and network calls themselves are Espressif's SDK and the backend,
/// neither of which is worth mocking here. What is worth pinning is the state
/// the UI reads: which steps count as busy, and that a failure carries a
/// message a user can act on.
void main() {
  group('ProvisioningState.isBusy', () {
    test('idle is not busy', () {
      expect(const ProvisioningState().isBusy, isFalse);
    });

    test('terminal states are not busy', () {
      for (final step in [ProvisioningStep.done, ProvisioningStep.failed]) {
        expect(ProvisioningState(step: step).isBusy, isFalse,
            reason: '$step should leave the UI interactive');
      }
    });

    test('deviceFound is not busy — the user acts next', () {
      // Devices are listed and the flow waits for a selection. Marking this
      // busy would disable the very controls the user needs.
      expect(
        const ProvisioningState(step: ProvisioningStep.deviceFound).isBusy,
        isFalse,
      );
    });

    test('in-flight steps are busy', () {
      for (final step in [
        ProvisioningStep.requestingPermissions,
        ProvisioningStep.scanning,
        ProvisioningStep.connecting,
        ProvisioningStep.scanningNetworks,
        ProvisioningStep.sendingCredentials,
        ProvisioningStep.claiming,
      ]) {
        expect(ProvisioningState(step: step).isBusy, isTrue,
            reason: '$step should block re-entry');
      }
    });
  });

  group('copyWith', () {
    test('carries values forward', () {
      const s = ProvisioningState(
        step: ProvisioningStep.deviceFound,
        devices: ['GG-aabbcc'],
        selectedDevice: 'GG-aabbcc',
      );
      final next = s.copyWith(step: ProvisioningStep.scanningNetworks);

      expect(next.devices, ['GG-aabbcc']);
      expect(next.selectedDevice, 'GG-aabbcc');
      expect(next.step, ProvisioningStep.scanningNetworks);
    });

    test('clearError wipes a stale message', () {
      // Without this, a failure message from an earlier attempt stays on
      // screen through the next one and reads as a fresh failure.
      const s = ProvisioningState(
        step: ProvisioningStep.failed,
        error: 'No pots found.',
      );
      final retry = s.copyWith(
        step: ProvisioningStep.scanning,
        clearError: true,
      );
      expect(retry.error, isNull);
    });

    test('an unrelated update keeps the error', () {
      const s = ProvisioningState(error: 'boom');
      expect(s.copyWith(step: ProvisioningStep.scanning).error, 'boom');
    });
  });

  group('device filtering', () {
    test('prefix isolates our pots from other BLE devices', () {
      // A scan in a normal room returns headphones, watches, TVs. The
      // firmware advertises GG-<last 6 of device id>.
      const all = [
        'GG-bb9f88',
        'AirPods Pro',
        'GG-a31f0c',
        'Some TV',
        'ggcode-laptop', // lowercase must not match
      ];
      final pots = all
          .where((n) => n.startsWith(ProvisioningService.devicePrefix))
          .toList();

      expect(pots, ['GG-bb9f88', 'GG-a31f0c']);
    });
  });
}
