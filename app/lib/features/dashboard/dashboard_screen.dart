import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../design/glass.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';
import 'pot_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pots = ref.watch(potsProvider);

    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: RefreshIndicator(
            backgroundColor: GGColors.surface,
            color: GGColors.volt,
            onRefresh: () async {
              ref.invalidate(potsProvider);
              await ref.read(potsProvider.future);
            },
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _Header()),
                pots.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: GGColors.volt),
                    ),
                  ),
                  error: (e, _) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Message(
                      icon: Icons.cloud_off_rounded,
                      title: 'Can\'t reach the server',
                      body: e.toString(),
                    ),
                  ),
                  data: (list) => list.isEmpty
                      ? const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _Message(
                            icon: Icons.eco_outlined,
                            title: 'No pots yet',
                            body: 'Pair a GreenGenius pot to start tracking it.',
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                              GGSpacing.m, 0, GGSpacing.m, GGSpacing.xxl),
                          sliver: SliverList.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: GGSpacing.m),
                            itemBuilder: (context, i) => _PotCard(pot: list[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
          GGSpacing.m, GGSpacing.l, GGSpacing.m, GGSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GREENGENIUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GGColors.volt,
              letterSpacing: 2.5,
            ),
          ),
          SizedBox(height: GGSpacing.xs),
          Text(
            'Your plants',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: GGColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faux glass, deliberately: this is a list item, and a real [GlassSurface]
/// here would mean one `saveLayer` per visible row every frame.
class _PotCard extends ConsumerWidget {
  const _PotCard({required this.pot});

  final Pot pot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(potSnapshotProvider(pot.id));

    final status = snapshot.valueOrNull?.health?.status ?? 'unknown';
    final score = snapshot.valueOrNull?.health?.score;
    final color = GGColors.statusColor(status);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PotDetailScreen(pot: pot)),
      ),
      child: FauxGlassSurface(
        padding: const EdgeInsets.all(GGSpacing.l),
        borderColor: status == 'good' || status == 'unknown'
            ? GGColors.glassBorderTop
            : color.withValues(alpha: 0.35),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
              ),
              alignment: Alignment.center,
              child: score != null
                  ? Text(
                      '$score',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    )
                  : Icon(Icons.eco_rounded, size: 22, color: color),
            ),
            const SizedBox(width: GGSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pot.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: GGColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pot.species?.displayName ?? 'Unidentified',
                    style: const TextStyle(
                      fontSize: 13,
                      color: GGColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: GGColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GGSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: GGColors.textTertiary),
          const SizedBox(height: GGSpacing.l),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: GGColors.textPrimary,
            ),
          ),
          const SizedBox(height: GGSpacing.s),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: GGColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
