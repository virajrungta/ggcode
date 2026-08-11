import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models.dart';
import '../../../core/providers.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';
import '../../onboarding/pair_pot_screen.dart';

/// The verdict shown at the top of the dashboard.
///
/// This replaced a header that read "Good morning / GreenGenius". Both lines
/// were decoration: the user knows what time it is, and they know which app
/// they just opened. It spent the most valuable region of the screen — the
/// top, where attention lands first — saying nothing about their plants, and
/// pushed the first real reading below the fold.
///
/// The guidance this follows is the "three-second rule" for monitoring
/// interfaces: someone should understand the state of the system within three
/// seconds of looking at it. So the headline is the answer, not a label.
enum Verdict {
  /// Nothing paired yet.
  empty,

  /// Paired, but no readings have arrived — distinct from "healthy".
  waiting,

  /// Something is wrong now and the user should act.
  needsAction,

  /// Drifting, worth knowing, not urgent.
  watch,

  /// Nothing to do.
  fine,
}

/// What the header needs to render, derived once rather than recomputed in
/// three places.
class DashboardSummary {
  const DashboardSummary({
    required this.verdict,
    required this.headline,
    required this.detail,
    this.subject,
  });

  final Verdict verdict;

  /// The sentence a user reads first. Written as a statement about their
  /// plants, never as a category name like "Warning".
  final String headline;

  /// Quieter supporting line: freshness, or which plant, or what to do.
  final String detail;

  /// The pot the headline is about, when it is about exactly one.
  final Pot? subject;

  Color get color => switch (verdict) {
        Verdict.needsAction => GGColors.bad,
        Verdict.watch => GGColors.warning,
        Verdict.fine => GGColors.good,
        _ => GGColors.unknown,
      };

  Color get textColor => switch (verdict) {
        Verdict.needsAction => GGColors.badText,
        Verdict.watch => GGColors.warningText,
        Verdict.fine => GGColors.goodText,
        _ => GGColors.unknownText,
      };

  IconData get icon => switch (verdict) {
        Verdict.needsAction => Icons.priority_high_rounded,
        Verdict.watch => Icons.error_outline_rounded,
        Verdict.fine => Icons.check_rounded,
        Verdict.waiting => Icons.hourglass_empty_rounded,
        Verdict.empty => Icons.add_rounded,
      };
}

/// Relative time, in the vocabulary people actually use for a plant sensor.
///
/// Deliberately coarse past an hour: "3h ago" is as actionable as "3h 12m
/// ago", and precision the reading does not have implies precision it does.
String freshness(DateTime? at) {
  if (at == null) return 'no readings yet';
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 90) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

/// Reduces every pot and its health into the single thing worth saying.
///
/// Worst-first: a user with one thriving plant and one dying one needs to be
/// told about the dying one. Averaging status across pots would report
/// "mostly fine" and bury the only fact that matters.
DashboardSummary summarise(WidgetRef ref, List<Pot> pots) {
  if (pots.isEmpty) {
    return const DashboardSummary(
      verdict: Verdict.empty,
      headline: 'Add your first plant',
      detail: 'Pair a GreenGenius pot to start tracking it',
    );
  }

  Pot? worstPot;
  HealthParameter? worstParam;
  int worstRank = -1;
  DateTime? newestReading;
  int assessed = 0;

  int rank(String status) => switch (status) {
        'bad' => 3,
        'warning' => 2,
        'good' => 1,
        _ => 0,
      };

  for (final pot in pots) {
    final snap = ref.watch(potSnapshotProvider(pot.id)).valueOrNull;
    if (snap == null) continue;

    final at = snap.reading?.time;
    final newest = newestReading;
    if (at != null && (newest == null || at.isAfter(newest))) {
      newestReading = at;
    }

    final health = snap.health;
    if (health == null) continue;
    assessed++;

    for (final p in health.parameters) {
      // 'unknown' means the sensor reported nothing, which is a hardware
      // problem rather than a plant problem. Surfacing it as the headline
      // would tell the user their plant is unwell when the probe is unplugged.
      if (p.status == 'unknown') continue;
      if (rank(p.status) > worstRank) {
        worstRank = rank(p.status);
        worstParam = p;
        worstPot = pot;
      }
    }
  }

  if (assessed == 0) {
    return DashboardSummary(
      verdict: Verdict.waiting,
      headline: pots.length == 1
          ? 'Waiting on ${pots.first.name}'
          : 'Waiting for readings',
      detail: newestReading == null
          ? 'No readings have arrived yet'
          : 'Last reading ${freshness(newestReading)}',
      subject: pots.length == 1 ? pots.first : null,
    );
  }

  final many = pots.length > 1;
  final name = worstPot?.name ?? pots.first.name;

  if (worstRank >= 2 && worstParam != null) {
    // The care engine already writes these for humans ("Soil is dry — water
    // within a day"). Re-phrasing them here would mean maintaining the same
    // sentence in two places and letting them drift apart.
    return DashboardSummary(
      verdict: worstRank == 3 ? Verdict.needsAction : Verdict.watch,
      headline: many ? '$name needs you' : worstParam.message,
      detail: many ? worstParam.message : 'Updated ${freshness(newestReading)}',
      subject: worstPot,
    );
  }

  return DashboardSummary(
    verdict: Verdict.fine,
    headline: many
        ? 'All ${pots.length} plants are happy'
        : '${pots.first.name} is thriving',
    detail: 'Updated ${freshness(newestReading)}',
    subject: many ? null : pots.first,
  );
}

/// Collapsing header whose expanded state is the verdict and whose collapsed
/// state keeps the status legible as a dot plus a short line.
///
/// The status survives the collapse on purpose: scrolling to look at a chart
/// should not hide whether anything is wrong.
class StatusHeader extends ConsumerWidget {
  const StatusHeader({super.key, required this.pots});

  final List<Pot> pots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summarise(ref, pots);

    return SliverAppBar(
      pinned: true,
      expandedHeight: 178,
      backgroundColor: GGColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: GGSpacing.s),
          child: GGTappable(
            radius: GGRadius.round,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PairPotScreen()),
            ),
            child: const GGIconTile(icon: Icons.add_rounded, size: 38),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: GGSpacing.m),
          child: GGTappable(
            radius: GGRadius.round,
            onTap: () {},
            child: const GGIconTile(icon: Icons.person_rounded, size: 38),
          ),
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final top = MediaQuery.of(context).padding.top;
          // 0 collapsed, 1 fully expanded.
          final t = ((constraints.maxHeight - top - kToolbarHeight) /
                  (178 - kToolbarHeight))
              .clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            titlePadding: EdgeInsets.only(
              left: 20,
              // Leave room for the action buttons when collapsed, so a long
              // headline cannot slide underneath them.
              right: t < 0.5 ? 104 : 20,
              bottom: 14 + 4 * t,
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Eyebrow(summary: s, t: t),
                Text(
                  s.headline,
                  maxLines: t > 0.5 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    // Shrinks rather than swapping between two widgets, so the
                    // headline glides instead of popping.
                    fontSize: 17 + 9 * t,
                    fontWeight: FontWeight.w800,
                    color: GGColors.textPrimary,
                    letterSpacing: -0.3 - 0.4 * t,
                    height: 1.18,
                  ),
                ),
                // Detail is the first thing to go: at rest there is only room
                // for the status dot and one line.
                ClipRect(
                  child: Align(
                    heightFactor: t,
                    alignment: Alignment.topLeft,
                    child: Opacity(
                      opacity: t,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          s.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: kFontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: GGColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Status dot plus label, above the headline.
///
/// Carries the state twice — colour *and* an icon plus a word — because
/// colour alone is not readable to everyone, and this is the one element on
/// the screen that has to survive a three-second glance.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.summary, required this.t});

  final DashboardSummary summary;
  final double t;

  @override
  Widget build(BuildContext context) {
    final label = switch (summary.verdict) {
      Verdict.needsAction => 'Needs attention',
      Verdict.watch => 'Keep an eye on it',
      Verdict.fine => 'All good',
      Verdict.waiting => 'Waiting',
      Verdict.empty => 'Get started',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: summary.color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(summary.icon, size: 11, color: summary.textColor),
          ),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: summary.textColor,
              // Tracking is what makes a short uppercase label read as a
              // deliberate eyebrow rather than as shouting.
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}
