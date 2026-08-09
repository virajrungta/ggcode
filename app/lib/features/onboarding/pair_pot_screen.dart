import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/provisioning_service.dart';
import '../../design/components.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';
import 'provisioning_controller.dart';

class PairPotScreen extends ConsumerStatefulWidget {
  const PairPotScreen({super.key});

  @override
  ConsumerState<PairPotScreen> createState() => _PairPotScreenState();
}

class _PairPotScreenState extends ConsumerState<PairPotScreen> {
  final _claimCode = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _potName = TextEditingController(text: 'My Plant');
  bool _obscure = true;

  @override
  void dispose() {
    _claimCode.dispose();
    _ssid.dispose();
    _password.dispose();
    _potName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(provisioningControllerProvider);
    final ctrl = ref.read(provisioningControllerProvider.notifier);

    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Pair a pot')),
        body: state.step == ProvisioningStep.done
            ? _Success(onDone: () => Navigator.of(context).pop())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _StepCard(
                    number: 1,
                    title: 'Find your pot',
                    child: _FindStep(state: state, ctrl: ctrl),
                  ),
                  const SizedBox(height: GGSpacing.m),
                  _StepCard(
                    number: 2,
                    title: 'Enter the setup code',
                    enabled: state.selectedDevice != null,
                    child: _CodeStep(
                      controller: _claimCode,
                      state: state,
                      onLoadNetworks: () =>
                          ctrl.loadNetworks(_claimCode.text.trim()),
                    ),
                  ),
                  const SizedBox(height: GGSpacing.m),
                  _StepCard(
                    number: 3,
                    title: 'Connect to Wi-Fi',
                    enabled: state.networks.isNotEmpty,
                    child: _WifiStep(
                      state: state,
                      ssid: _ssid,
                      password: _password,
                      potName: _potName,
                      obscure: _obscure,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onSubmit: () => ctrl.provisionAndClaim(
                        claimCode: _claimCode.text.trim(),
                        ssid: _ssid.text.trim(),
                        passphrase: _password.text,
                        potName: _potName.text.trim(),
                      ),
                    ),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: GGSpacing.l),
                    _ErrorPanel(message: state.error!),
                  ],
                ],
              ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.child,
    this.enabled = true,
  });

  final int number;
  final String title;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Dimmed rather than hidden: seeing the whole flow up front tells people
    // how long this takes, which matters when they are holding a plant pot.
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          padding: const EdgeInsets.all(GGSpacing.m + 2),
          decoration: BoxDecoration(
            color: GGColors.surface,
            borderRadius: GGRadius.lAll,
            border: Border.all(color: GGColors.outline),
            boxShadow: ggCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: GGColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: GGColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: GGSpacing.s + 2),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GGColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GGSpacing.m),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _FindStep extends StatelessWidget {
  const _FindStep({required this.state, required this.ctrl});

  final ProvisioningState state;
  final ProvisioningController ctrl;

  @override
  Widget build(BuildContext context) {
    final scanning = state.step == ProvisioningStep.scanning ||
        state.step == ProvisioningStep.requestingPermissions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.devices.isEmpty)
          const Text(
            'Your pot broadcasts for setup only until it has been connected '
            'once. Make sure it is powered on and nearby.',
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 13,
              color: GGColors.textSecondary,
              height: 1.45,
            ),
          ),
        for (final d in state.devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GGTappable(
              radius: GGRadius.m,
              onTap: () => ctrl.selectDevice(d),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: GGSpacing.m - 4, vertical: GGSpacing.s + 4),
                decoration: BoxDecoration(
                  color: d == state.selectedDevice
                      ? GGColors.primaryContainer
                      : GGColors.surfaceMuted,
                  borderRadius: GGRadius.mAll,
                  border: Border.all(
                    color: d == state.selectedDevice
                        ? GGColors.primary
                        : GGColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      d == state.selectedDevice
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 19,
                      color: d == state.selectedDevice
                          ? GGColors.primary
                          : GGColors.textTertiary,
                    ),
                    const SizedBox(width: GGSpacing.s + 2),
                    Text(
                      d,
                      style: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: GGColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: GGSpacing.s),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            onPressed: scanning ? null : ctrl.scan,
            icon: scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.bluetooth_searching_rounded, size: 18),
            label: Text(scanning
                ? 'Searching…'
                : state.devices.isEmpty
                    ? 'Search for pots'
                    : 'Search again'),
          ),
        ),
      ],
    );
  }
}

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    required this.controller,
    required this.state,
    required this.onLoadNetworks,
  });

  final TextEditingController controller;
  final ProvisioningState state;
  final VoidCallback onLoadNetworks;

  @override
  Widget build(BuildContext context) {
    final busy = state.step == ProvisioningStep.scanningNetworks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Find the 9-character code printed on the base of your pot.',
          style: TextStyle(
            fontFamily: kFontFamily,
            fontSize: 13,
            color: GGColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: GGSpacing.m),
        TextField(
          controller: controller,
          // The code is uppercase alphanumeric with a dash. Forcing the case
          // avoids a mismatch that would surface as an unhelpful crypto error
          // from the provisioning handshake.
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(9),
          ],
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
          decoration: InputDecoration(
            hintText: 'ABCD-1234',
            filled: true,
            fillColor: GGColors.surfaceMuted,
            border: OutlineInputBorder(
              borderRadius: GGRadius.mAll,
              borderSide: const BorderSide(color: GGColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: GGRadius.mAll,
              borderSide: const BorderSide(color: GGColors.outline),
            ),
          ),
        ),
        const SizedBox(height: GGSpacing.m),
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: busy ? null : onLoadNetworks,
            child: Text(busy ? 'Talking to your pot…' : 'Continue'),
          ),
        ),
      ],
    );
  }
}

class _WifiStep extends StatelessWidget {
  const _WifiStep({
    required this.state,
    required this.ssid,
    required this.password,
    required this.potName,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final ProvisioningState state;
  final TextEditingController ssid;
  final TextEditingController password;
  final TextEditingController potName;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final busy = state.step == ProvisioningStep.sendingCredentials ||
        state.step == ProvisioningStep.claiming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'These are the networks your pot can see — not your phone. '
          'Pots only support 2.4GHz.',
          style: TextStyle(
            fontFamily: kFontFamily,
            fontSize: 13,
            color: GGColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: GGSpacing.m),
        if (state.networks.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: ssid.text.isEmpty ? null : ssid.text,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: GGColors.surfaceMuted,
              border: OutlineInputBorder(borderRadius: GGRadius.mAll),
            ),
            hint: const Text('Choose a network'),
            items: [
              for (final n in state.networks)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (v) => ssid.text = v ?? '',
          ),
        const SizedBox(height: GGSpacing.m),
        TextField(
          controller: password,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: 'Wi-Fi password',
            filled: true,
            fillColor: GGColors.surfaceMuted,
            border: OutlineInputBorder(borderRadius: GGRadius.mAll),
            suffixIcon: IconButton(
              icon: Icon(obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: GGSpacing.m),
        TextField(
          controller: potName,
          decoration: InputDecoration(
            labelText: 'Name this pot',
            filled: true,
            fillColor: GGColors.surfaceMuted,
            border: OutlineInputBorder(borderRadius: GGRadius.mAll),
          ),
        ),
        const SizedBox(height: GGSpacing.m),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.wifi_rounded, size: 18),
            label: Text(
              state.step == ProvisioningStep.claiming
                  ? 'Registering your pot…'
                  : busy
                      ? 'Connecting…'
                      : 'Connect',
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GGSpacing.m),
      decoration: BoxDecoration(
        color: GGColors.badContainer,
        borderRadius: GGRadius.lAll,
        border: Border.all(color: GGColors.bad.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 20, color: GGColors.bad),
          const SizedBox(width: GGSpacing.m - 4),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: GGColors.badText,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GGSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GGIconTile(
              icon: Icons.check_rounded, size: 84, iconSize: 40),
          const SizedBox(height: GGSpacing.l),
          const Text(
            'Your pot is connected',
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: GGColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: GGSpacing.s),
          const Text(
            'Readings will start appearing within a few minutes. '
            'Calibrate the soil probe next for accurate moisture.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 14,
              color: GGColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: GGSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(onPressed: onDone, child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}

/// Uppercases as you type. The claim code is the provisioning
/// proof-of-possession, and a case mismatch fails inside the crypto handshake
/// with an error no user could act on.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
