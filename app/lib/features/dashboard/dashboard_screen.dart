import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';
import '../onboarding/pair_pot_screen.dart';
import 'widgets/add_pot_card.dart';
import 'widgets/action_strip.dart';
import 'widgets/attention_card.dart';
import 'widgets/bento_metrics.dart';
import 'widgets/pot_hero.dart';
import 'widgets/status_header.dart';

/// Home.
///
/// Structure, top to bottom: a collapsing large title, a swipeable hero card
/// per pot, an asymmetric bento grid of that pot's readings, then the
/// attention card.
///
/// Deliberately not the banner → quick-action-row → section-list shape: that
/// arrangement is everywhere, and it buries the actual reading two thirds of
/// the way down the page behind a row of buttons. Here the number a user
/// opened the app for is above the fold.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final pots = ref.watch(potsProvider);

    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          backgroundColor: GGColors.surface,
          color: GGColors.primary,
          edgeOffset: 100,
          onRefresh: () async {
            ref.invalidate(potsProvider);
            await ref.read(potsProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              StatusHeader(pots: pots.valueOrNull ?? const []),
              ...pots.when(
                loading: () => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: GGEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: "Can't reach the server",
                      body: e.toString(),
                    ),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: GGEmptyState(
                            icon: Icons.eco_rounded,
                            title: 'No pots yet',
                            body: 'Pair a GreenGenius pot to start tracking it.',
                            action: SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const PairPotScreen()),
                                ),
                                icon: const Icon(
                                    Icons.bluetooth_searching_rounded, size: 18),
                                label: const Text('Pair a pot'),
                              ),
                            ),
                          ),
                        ),
                      ]
                    : _content(list),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(List<Pot> pots) => [
        // Above the hero on purpose. When the plant needs something, that is
        // the reason the app was opened, and it should not sit below a card
        // the user has to scroll past.
        SliverToBoxAdapter(
          child: Padding(
            padding: GGSpacing.page,
            child: ActionStrip(pots: pots),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: PotHeroCarousel(pots: pots).entrance(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.l)),
        SliverToBoxAdapter(
          child: Padding(
            padding: GGSpacing.page,
            child: _Readings(pot: pots.first).entrance(index: 1),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.l)),
        SliverToBoxAdapter(
          child: Padding(
            padding: GGSpacing.page,
            child: _Attention(pots: pots).entrance(index: 2),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.l)),
        SliverToBoxAdapter(
          child: Padding(
            padding: GGSpacing.page,
            child: const AddPotCard().entrance(index: 3),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ];
}

/// Bento readings for a pot, wired to its snapshot and 48h series.
class _Readings extends ConsumerWidget {
  const _Readings({required this.pot});

  final Pot pot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(potSnapshotProvider(pot.id));
    final series = ref.watch(potSeriesProvider(pot.id)).valueOrNull ?? const [];

    final params = snapshot.valueOrNull?.health?.parameters ?? const [];
    if (params.isEmpty) return const SizedBox.shrink();

    // Last ~12 hourly buckets: enough to show a shape, few enough that the
    // line stays legible at 44px tall.
    List<double> tail(double? Function(SeriesPoint) read) {
      final v = series.map(read).whereType<double>().toList();
      return v.length <= 12 ? v : v.sublist(v.length - 12);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Just the section header: the pot's name is already on the hero
        // card immediately above, and repeating it read as a second heading
        // for the same thing.
        const GGSectionHeader(title: 'Right now'),
        const SizedBox(height: GGSpacing.m),
        BentoMetrics(
          parameters: params,
          soilHistory: tail((p) => p.soilPct),
          lightHistory: tail((p) => p.lux),
        ),
      ],
    );
  }
}

class _Attention extends ConsumerWidget {
  const _Attention({required this.pots});

  final List<Pot> pots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = <({Pot pot, Health health})>[];
    for (final pot in pots) {
      final health = ref.watch(potSnapshotProvider(pot.id)).valueOrNull?.health;
      if (health != null) entries.add((pot: pot, health: health));
    }
    return AttentionCard(entries: entries);
  }
}
