import 'package:flutter/material.dart';

import '../../../core/api/models.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';

/// The single most important thing to do right now, across all pots.
///
/// A dashboard that only lists pots makes the user do the triage themselves.
/// This surfaces the worst outstanding issue and names the plant, so the answer
/// to "does anything need me?" is readable without opening anything.
class AttentionCard extends StatelessWidget {
  const AttentionCard({super.key, required this.entries});

  /// (pot, health) pairs for every pot with a loaded snapshot.
  final List<({Pot pot, Health health})> entries;

  @override
  Widget build(BuildContext context) {
    final bad = entries.where((e) => e.health.status == 'bad').toList();
    final warning = entries.where((e) => e.health.status == 'warning').toList();

    if (bad.isEmpty && warning.isEmpty) {
      return _AllGood(count: entries.length);
    }

    final worst = bad.isNotEmpty ? bad.first : warning.first;
    final color = GGColors.statusColor(worst.health.status);
    final issue = worst.health.issues.isNotEmpty
        ? worst.health.issues.first
        : 'Conditions are outside the ideal range';
    final action = worst.health.recommendations.isNotEmpty
        ? worst.health.recommendations.first
        : null;

    final others = bad.length + warning.length - 1;

    return Container(
      padding: const EdgeInsets.all(GGSpacing.m + 2),
      decoration: BoxDecoration(
        color: GGColors.surface,
        borderRadius: GGRadius.lAll,
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: ggCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GGIconTile(
                icon: worst.health.status == 'bad'
                    ? Icons.priority_high_rounded
                    : Icons.error_outline_rounded,
                color: color,
                size: 42,
                iconSize: 20,
              ),
              const SizedBox(width: GGSpacing.m - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GGCaption('Needs attention', color: GGColors.statusText(worst.health.status)),
                    const SizedBox(height: 3),
                    Text(
                      worst.pot.name,
                      style: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: GGColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (others > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: GGColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(GGRadius.round),
                  ),
                  child: Text(
                    '+$others',
                    style: const TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: GGColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: GGSpacing.m),
          Text(
            issue,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: GGColors.textPrimary,
              height: 1.4,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: GGSpacing.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.arrow_forward_rounded,
                    size: 15, color: GGColors.primary),
                const SizedBox(width: GGSpacing.s),
                Expanded(
                  child: Text(
                    action,
                    style: const TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 13,
                      color: GGColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AllGood extends StatelessWidget {
  const _AllGood({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GGSpacing.m + 2),
      decoration: BoxDecoration(
        color: GGColors.surface,
        borderRadius: GGRadius.lAll,
        border: Border.all(color: GGColors.primary.withValues(alpha: 0.4)),
        boxShadow: ggCardShadow,
      ),
      child: Row(
        children: [
          const GGIconTile(
              icon: Icons.check_rounded, size: 42, iconSize: 20),
          const SizedBox(width: GGSpacing.m - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GGCaption('All good', color: GGColors.primaryDark),
                const SizedBox(height: 3),
                Text(
                  count == 0
                      ? 'Nothing to check yet'
                      : 'Every plant is in its ideal range',
                  style: const TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: GGColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
