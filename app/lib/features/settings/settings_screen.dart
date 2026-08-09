import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';
import '../onboarding/pair_pot_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            GGHeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const GGIconTile(icon: Icons.person_rounded, size: 52),
                      const SizedBox(width: GGSpacing.m),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontFamily: kFontFamily,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: GGColors.onPrimaryContainer,
                              letterSpacing: -0.8,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            'dev-user',
                            style: const TextStyle(
                              fontFamily: kFontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: GGColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ).entrance(),
            const SizedBox(height: GGSpacing.l),
            Padding(
              padding: GGSpacing.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GGSectionHeader(title: 'Connection').entrance(index: 1),
                  const SizedBox(height: GGSpacing.m),
                  _Group(
                    children: [
                      _Row(
                        icon: Icons.dns_rounded,
                        label: 'Backend',
                        value: resolveApiUrl(),
                      ),
                      const _Divider(),
                      const _Row(
                        icon: Icons.shield_outlined,
                        label: 'Auth mode',
                        value: 'Development',
                        // Deliberately visible: this build trusts a header
                        // instead of verifying tokens, and that should never
                        // be invisible to whoever is running it.
                        warn: true,
                      ),
                    ],
                  ).entrance(index: 2),
                  const SizedBox(height: GGSpacing.xl),
                  const GGSectionHeader(title: 'Device').entrance(index: 3),
                  const SizedBox(height: GGSpacing.m),
                  _Group(
                    children: [
                      _Row(
                        icon: Icons.bluetooth_rounded,
                        label: 'Pair a new pot',
                        chevron: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PairPotScreen()),
                        ),
                      ),
                      const _Divider(),
                      _Row(
                        icon: Icons.tune_rounded,
                        label: 'Calibrate soil sensor',
                        chevron: true,
                        onTap: () => _soon(context, 'Calibration'),
                      ),
                      const _Divider(),
                      _Row(
                        icon: Icons.system_update_rounded,
                        label: 'Firmware update',
                        chevron: true,
                        onTap: () => _soon(context, 'OTA updates'),
                      ),
                    ],
                  ).entrance(index: 4),
                  const SizedBox(height: GGSpacing.xl),
                  const GGSectionHeader(title: 'About').entrance(index: 5),
                  const SizedBox(height: GGSpacing.m),
                  const _Group(
                    children: [
                      _Row(
                        icon: Icons.info_outline_rounded,
                        label: 'Version',
                        value: '1.0.0 (dev)',
                      ),
                    ],
                  ).entrance(index: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming in a later build')),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GGColors.surface,
        borderRadius: GGRadius.lAll,
        border: Border.all(color: GGColors.outline),
        boxShadow: ggCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: GGColors.outline);
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.value,
    this.chevron = false,
    this.warn = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool chevron;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = warn ? GGColors.warning : GGColors.primary;
    final valueInk = warn ? GGColors.warningText : GGColors.textSecondary;

    return GGTappable(
      onTap: onTap,
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: GGSpacing.m, vertical: GGSpacing.m - 2),
        child: Row(
          children: [
            GGIconTile(icon: icon, color: accent, size: 36, iconSize: 17),
            const SizedBox(width: GGSpacing.m - 4),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: GGColors.textPrimary,
                ),
              ),
            ),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: valueInk,
                  ),
                ),
              ),
            if (chevron) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: GGColors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}
