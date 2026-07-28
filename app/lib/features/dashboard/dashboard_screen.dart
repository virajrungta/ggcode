import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';
import 'pot_detail_screen.dart';
import 'widgets/attention_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pots = ref.watch(potsProvider);

    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          backgroundColor: GGColors.surface,
          color: GGColors.volt,
          onRefresh: () async {
            ref.invalidate(potsProvider);
            await ref.read(potsProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(potCount: pots.valueOrNull?.length ?? 0)
                    .entrance(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.l)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: GGSpacing.page,
                  child: _Attention(pots: pots.valueOrNull ?? const [])
                      .entrance(index: 1),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.l)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: GGSpacing.page,
                  child: const _QuickActions().entrance(index: 2),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.xl)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: GGSpacing.page,
                  child: const GGSectionHeader(title: 'Your plants')
                      .entrance(index: 3),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: GGSpacing.m)),
              pots.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(GGSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: GGEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Can't reach the server",
                    body: e.toString(),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter(
                        child: GGEmptyState(
                          icon: Icons.eco_rounded,
                          title: 'No pots yet',
                          body: 'Pair a GreenGenius pot to start tracking it.',
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                        sliver: SliverList.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: GGSpacing.m),
                          itemBuilder: (context, i) =>
                              _PotCard(pot: list[i]).entrance(index: 4 + i),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.potCount});

  final int potCount;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    return GGHeroHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'GreenGenius',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: GGColors.textPrimary,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const GGIconTile(icon: Icons.person_rounded, size: 44),
            ],
          ),
          const SizedBox(height: GGSpacing.l),
          Container(
            padding: const EdgeInsets.all(GGSpacing.m - 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: GGRadius.mAll,
              border: Border.all(color: GGColors.glassBorderTop),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco_rounded, color: GGColors.volt, size: 20),
                const SizedBox(width: GGSpacing.m - 4),
                Expanded(
                  child: Text(
                    potCount == 0
                        ? 'No pots paired yet'
                        : '$potCount ${potCount == 1 ? 'plant' : 'plants'} being monitored',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
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

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GGQuickAction(
            icon: Icons.add_a_photo_rounded,
            label: 'Identify',
            onTap: () => _soon(context, 'Plant identification'),
          ),
        ),
        const SizedBox(width: GGSpacing.m - 4),
        Expanded(
          child: GGQuickAction(
            icon: Icons.bluetooth_searching_rounded,
            label: 'Pair pot',
            color: GGColors.cyan,
            onTap: () => _soon(context, 'Pot pairing'),
          ),
        ),
        const SizedBox(width: GGSpacing.m - 4),
        Expanded(
          child: GGQuickAction(
            icon: Icons.water_drop_rounded,
            label: 'Water all',
            color: GGColors.volt,
            onTap: () => _soon(context, 'Bulk watering'),
          ),
        ),
      ],
    );
  }

  // These land in Phases 4 and 6. Saying so is better than a dead button.
  static void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming in a later build')),
    );
  }
}

class _PotCard extends ConsumerWidget {
  const _PotCard({required this.pot});

  final Pot pot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(potSnapshotProvider(pot.id));
    final health = snapshot.valueOrNull?.health;
    final reading = snapshot.valueOrNull?.reading;
    final status = health?.status ?? 'unknown';
    final color = GGColors.statusColor(status);
    final online = snapshot.valueOrNull?.online ?? false;

    return GGTappable(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PotDetailScreen(pot: pot)),
      ),
      child: Container(
        padding: const EdgeInsets.all(GGSpacing.m + 2),
        decoration: BoxDecoration(
          borderRadius: GGRadius.lAll,
          color: GGColors.surface1,
          border: Border.all(color: color.withValues(alpha: 0.30)),
          boxShadow: ggGlow(color, opacity: 0.12, blur: 22),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _ScoreBadge(score: health?.score, color: color),
                const SizedBox(width: GGSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pot.name,
                        style: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: GGColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        pot.species?.displayName ?? 'Unidentified plant',
                        style: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 13,
                          color: GGColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GGStatusPill(
                  label: online ? 'Live' : 'Offline',
                  color: online ? GGColors.volt : GGColors.textTertiary,
                  glowing: online,
                ),
              ],
            ),
            if (reading != null) ...[
              const SizedBox(height: GGSpacing.m),
              Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
              const SizedBox(height: GGSpacing.m),
              Row(
                children: [
                  _MiniStat(
                    icon: Icons.water_drop_rounded,
                    value: reading.soilPct,
                    unit: '%',
                    color: GGColors.cyan,
                  ),
                  _MiniStat(
                    icon: Icons.thermostat_rounded,
                    value: reading.tempC,
                    unit: '°',
                    color: GGColors.amber,
                  ),
                  _MiniStat(
                    icon: Icons.wb_sunny_rounded,
                    value: reading.lux,
                    unit: 'lx',
                    color: GGColors.volt,
                    integer: true,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, required this.color});

  final int? score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      alignment: Alignment.center,
      child: score != null
          ? Text(
              '$score',
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            )
          : Icon(Icons.eco_rounded, size: 22, color: color),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.unit,
    required this.color,
    this.integer = false,
  });

  final IconData icon;
  final double? value;
  final String unit;
  final Color color;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    // A dash, never a fabricated 0 — a missing sensor and a reading of zero
    // are different things.
    final text = value == null
        ? '—'
        : integer || value!.abs() >= 100
            ? '${value!.round()}$unit'
            : '${value!.toStringAsFixed(1)}$unit';

    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: GGColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


/// Collects loaded snapshots so the attention card can rank across pots.
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
