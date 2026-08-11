import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/providers.dart';
import '../../../design/tokens.dart';
import 'status_header.dart';

/// The one action worth offering right now, or nothing at all.
///
/// Deliberately not the usual row of four quick-action buttons under the
/// banner. That pattern shows every action permanently, at equal weight, which
/// makes none of them look urgent and costs a full row of the screen even when
/// there is nothing to do. Here the strip appears only when the plant actually
/// needs something, so its presence is itself the signal.
class ActionStrip extends ConsumerStatefulWidget {
  const ActionStrip({super.key, required this.pots});

  final List<Pot> pots;

  @override
  ConsumerState<ActionStrip> createState() => _ActionStripState();
}

class _ActionStripState extends ConsumerState<ActionStrip> {
  bool _busy = false;

  /// Matches the backend's own cap. The firmware enforces the real limits
  /// regardless — this is only about not asking for something that will be
  /// rejected.
  static const _durationSeconds = 5.0;

  Future<void> _water(Pot pot) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .water(pot.id, durationSeconds: _durationSeconds);
      // The reading that proves it worked arrives on the pot's next telemetry
      // POST, so refresh rather than optimistically redrawing.
      ref.invalidate(potSnapshotProvider(pot.id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Watering — the pot will confirm shortly')),
      );
    } on ApiException catch (e) {
      // The backend writes these for humans ("Soil is already at 88% moisture.
      // Watering now risks root rot."), so show its text rather than a
      // generic failure.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = summarise(ref, widget.pots);

    // Nothing wrong, or nothing specific enough to act on.
    if (s.verdict != Verdict.needsAction && s.verdict != Verdict.watch) {
      return const SizedBox.shrink();
    }
    final pot = s.subject ?? widget.pots.first;

    // Only offer watering when the pot can actually water itself. Offering a
    // button that cannot work is worse than offering none.
    final snap = ref.watch(potSnapshotProvider(pot.id)).valueOrNull;
    final soil = snap?.health?.parameters
        .where((p) => p.parameter == 'soil_pct')
        .firstOrNull;
    final dry = soil != null && (soil.status == 'bad' || soil.status == 'warning');
    if (!dry || pot.deviceId == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: GGSpacing.l),
      child: Container(
        padding: const EdgeInsets.all(GGSpacing.s + 2),
        decoration: BoxDecoration(
          color: GGColors.statusContainer(soil.status),
          borderRadius: GGRadius.lAll,
          border: Border.all(
            color: GGColors.statusColor(soil.status).withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: GGSpacing.s - 2),
            Icon(Icons.water_drop_rounded,
                size: 19, color: GGColors.statusText(soil.status)),
            const SizedBox(width: GGSpacing.s + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.pots.length > 1 ? pot.name : 'Soil is dry',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GGColors.statusText(soil.status),
                    ),
                  ),
                  if (soil.value != null)
                    Text(
                      '${soil.value!.round()}% now'
                      '${soil.idealRange != null ? ' · target ${soil.idealRange!.min.round()}–${soil.idealRange!.max.round()}%' : ''}',
                      style: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: GGColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: GGSpacing.s),
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: _busy ? null : () => _water(pot),
                style: FilledButton.styleFrom(
                  backgroundColor: GGColors.statusText(soil.status),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Water'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
