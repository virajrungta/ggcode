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

/// A headline-length phrase for a failing parameter.
///
/// The care engine's own message is a full sentence written as body copy
/// ("Soil is very dry at 12% — water thoroughly today to avoid root damage").
/// Setting that as a 26px display headline truncated it mid-word, which is
/// worse than useless: the reader gets the alarm without the instruction. The
/// sentence now runs as the detail line, where it fits, and this supplies
/// something short enough to be a heading.
String shortVerdict(HealthParameter p) {
  final r = p.idealRange;
  final v = p.value;
  // Null when there is no range to compare against, in which case "low" is the
  // safer assumption for soil and the label alone is used elsewhere.
  final high = (r != null && v != null) ? v > r.max : false;

  return switch (p.parameter) {
    'soil_pct' => high ? 'Soil is too wet' : 'Needs water',
    'temp_c' => high ? 'Too warm' : 'Too cold',
    'rh' => high ? 'Air is too humid' : 'Air is too dry',
    'lux' => high ? 'Too much light' : 'Not enough light',
    _ => p.label,
  };
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
  int usable = 0;

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
      usable++;
      if (rank(p.status) > worstRank) {
        worstRank = rank(p.status);
        worstParam = p;
        worstPot = pot;
      }
    }
  }

  // Health came back but every parameter was 'unknown', so there is nothing
  // to judge. Falling through to the "nothing bad found" branch below would
  // print a confident green "is thriving" for a pot whose probes are
  // unplugged — worse than saying nothing, because it looks like an answer.
  if (assessed > 0 && usable == 0) {
    return DashboardSummary(
      verdict: Verdict.waiting,
      headline: pots.length == 1
          ? 'No readings from ${pots.first.name}'
          : 'No sensor readings yet',
      detail: newestReading == null
          ? 'Check the sensors are connected'
          : 'Pot last checked in ${freshness(newestReading)}',
      subject: pots.length == 1 ? pots.first : null,
    );
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
    final short = shortVerdict(worstParam);
    return DashboardSummary(
      verdict: worstRank == 3 ? Verdict.needsAction : Verdict.watch,
      // Which plant, but only when that is ambiguous. With one pot its name is
      // already on the hero card below.
      headline: many ? '$name: $short' : short,
      // The care engine's sentence, verbatim. It is the instruction, and it is
      // the reason not to re-derive this wording in the UI.
      detail: worstParam.message,
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

/// Collapsing header, built on [SliverPersistentHeader] rather than
/// [SliverAppBar] + [FlexibleSpaceBar].
///
/// FlexibleSpaceBar was the wrong primitive and produced three visible bugs on
/// device: it applies `expandedTitleScale` (default **1.5**) on top of the
/// title's own text style, so a headline animated from 17 to 26px actually
/// drew at ~39px and swallowed a third of the screen; its title column is
/// bottom-anchored and scaled, which threw the eyebrow up into the status bar;
/// and the composed column overflowed midway through the collapse.
///
/// A persistent header delegate gives the shrink fraction directly and lays
/// out exactly what it is told to.
///
/// The two states cross-fade rather than interpolating one layout. That is the
/// same thing iOS large titles and Material's large top app bar do, and it
/// removes the whole class of overflow bugs above: each state is laid out in
/// its own box at its own fixed size.
class StatusHeader extends ConsumerWidget {
  const StatusHeader({super.key, required this.pots});

  final List<Pot> pots;

  /// Height of the expanded block *below* the pinned bar.
  ///
  /// Fits an eyebrow (18), one line of 26px headline (30), and two lines of
  /// 13px detail (35), plus the gaps. Both text runs are capped, so no
  /// care-engine string can outgrow it.
  static const double _expandedBlock = 104;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = summarise(ref, pots);
    final top = MediaQuery.of(context).padding.top;

    // With nothing paired the body already shows a full empty state with the
    // same words. Repeating them in a large header said "add your first
    // plant" three times on one screen, so the header stays quiet instead.
    final collapsedOnly = summary.verdict == Verdict.empty;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderDelegate(
        summary: summary,
        topPadding: top,
        expandedBlock: collapsedOnly ? 0 : _expandedBlock,
        showTitleWhenCollapsed: !collapsedOnly,
      ),
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.summary,
    required this.topPadding,
    required this.expandedBlock,
    required this.showTitleWhenCollapsed,
  });

  final DashboardSummary summary;
  final double topPadding;
  final double expandedBlock;
  final bool showTitleWhenCollapsed;

  static const double _bar = 56;

  @override
  double get minExtent => topPadding + _bar;

  @override
  double get maxExtent => topPadding + _bar + expandedBlock;

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.summary.headline != summary.headline ||
      old.summary.detail != summary.detail ||
      old.summary.verdict != summary.verdict ||
      old.topPadding != topPadding ||
      old.expandedBlock != expandedBlock;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final range = maxExtent - minExtent;
    // 1 fully expanded, 0 collapsed.
    final t = range <= 0 ? 0.0 : (1 - shrinkOffset / range).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: GGColors.bg,
        // A hairline only once collapsed. Without it, cards scrolling under
        // the pinned bar have nothing to stop against and the bar stops
        // reading as a separate layer. Fades in with the collapse so it is
        // absent at rest, where the header and page are one surface.
        border: Border(
          bottom: BorderSide(
            color: GGColors.outline.withValues(alpha: (1 - t).clamp(0.0, 1.0)),
            width: t < 1 ? 1 : 0,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Expanded block. Sits below the bar, so the actions never overlap
          // it and it cannot ride up into the status bar.
          if (expandedBlock > 0)
            Positioned(
              left: 20,
              right: 20,
              top: topPadding + _bar,
              height: expandedBlock,
              child: IgnorePointer(
                ignoring: t < 0.5,
                child: Opacity(
                  // Gone well before the bar finishes collapsing, so the two
                  // states never both read as the page heading.
                  opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
                  child: _Expanded(summary: summary),
                ),
              ),
            ),

          // Pinned bar: inline title on the left, actions on the right.
          Positioned(
            left: 0,
            right: 0,
            top: topPadding,
            height: _bar,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: showTitleWhenCollapsed
                      ? Opacity(
                          opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                          child: _Inline(summary: summary),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: GGSpacing.s),
                GGTappable(
                  radius: GGRadius.round,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PairPotScreen()),
                  ),
                  child: const GGIconTile(icon: Icons.add_rounded, size: 38),
                ),
                const SizedBox(width: GGSpacing.s),
                GGTappable(
                  radius: GGRadius.round,
                  onTap: () {},
                  child: const GGIconTile(icon: Icons.person_rounded, size: 38),
                ),
                const SizedBox(width: GGSpacing.m),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The collapsed state: a status dot and one line, so scrolling to a chart
/// never hides whether something is wrong.
class _Inline extends StatelessWidget {
  const _Inline({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Dot(summary: summary, size: 16, iconSize: 10),
        const SizedBox(width: GGSpacing.s),
        Expanded(
          child: Text(
            summary.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: GGColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// The expanded state: eyebrow, verdict, freshness.
class _Expanded extends StatelessWidget {
  const _Expanded({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final label = switch (summary.verdict) {
      Verdict.needsAction => 'Needs attention',
      Verdict.watch => 'Keep an eye on it',
      Verdict.fine => 'All good',
      Verdict.waiting => 'Waiting',
      Verdict.empty => 'Get started',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(summary: summary, size: 18, iconSize: 11),
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
        const SizedBox(height: 6),
        Text(
          summary.headline,
          // One line, because the headline is now a short phrase. A second
          // line here would push the detail out of the block.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kFontFamily,
            // 26 and no scaling widget above it. The previous header set the
            // same number and drew at 39.
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: GGColors.textPrimary,
            letterSpacing: -0.7,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          summary.detail,
          // Two, so the care engine's full instruction fits rather than being
          // cut off after "water thoroughly today to avoid roo…".
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: GGColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Status carried by colour *and* an icon, because colour alone is not
/// readable to everyone and this is the element that has to survive a
/// three-second glance.
class _Dot extends StatelessWidget {
  const _Dot({required this.summary, required this.size, required this.iconSize});

  final DashboardSummary summary;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: summary.color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(summary.icon, size: iconSize, color: summary.textColor),
    );
  }
}
