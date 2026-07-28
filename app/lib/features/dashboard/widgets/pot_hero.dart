import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models.dart';
import '../../../core/providers.dart';
import '../../../design/components.dart';
import '../../../design/glass.dart';
import '../../../design/tokens.dart';
import '../pot_detail_screen.dart';
import 'health_ring.dart';

/// Swipeable hero card, one page per pot.
///
/// Replaces the list-of-rows layout. For a device app the plant *is* the
/// subject, not a row in an inventory — the same reason a camera app leads
/// with the live tile rather than a list of camera names.
///
/// `viewportFraction` below 1 leaves the neighbouring cards peeking at the
/// edges, which is what tells the user there is more to swipe to. Without it a
/// PageView is indistinguishable from a static card and nobody swipes.
class PotHeroCarousel extends ConsumerStatefulWidget {
  const PotHeroCarousel({super.key, required this.pots});

  final List<Pot> pots;

  @override
  ConsumerState<PotHeroCarousel> createState() => _PotHeroCarouselState();
}

class _PotHeroCarouselState extends ConsumerState<PotHeroCarousel> {
  late final PageController _controller =
      PageController(viewportFraction: widget.pots.length > 1 ? 0.88 : 1.0);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 296,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.pots.length,
            onPageChanged: (i) => setState(() => _page = i),
            padEnds: false,
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsets.only(
                left: widget.pots.length > 1 ? 0 : 0,
                right: widget.pots.length > 1 ? GGSpacing.m - 4 : 0,
              ),
              child: _HeroCard(pot: widget.pots[i]),
            ),
          ),
        ),
        if (widget.pots.length > 1) ...[
          const SizedBox(height: GGSpacing.m),
          _Dots(count: widget.pots.length, active: _page),
        ],
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: GGDuration.fast,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active ? GGColors.primary : GGColors.outlineStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.pot});

  final Pot pot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(potSnapshotProvider(pot.id));
    final health = snapshot.valueOrNull?.health;
    final online = snapshot.valueOrNull?.online ?? false;
    final status = health?.status ?? 'unknown';

    return GGTappable(
      radius: GGRadius.xl,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PotDetailScreen(pot: pot)),
      ),
      child: GlassSurface(
        blur: GGBlur.heavy,
        radius: GGRadius.xl,
        glowColor: GGColors.statusColor(status),
        padding: const EdgeInsets.symmetric(
            vertical: GGSpacing.l, horizontal: GGSpacing.l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HealthRing(score: health?.score, status: status, size: 132),
            const SizedBox(height: GGSpacing.m),
            Text(
              pot.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: GGColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pot.species?.displayName ?? 'Unidentified plant',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: GGColors.textSecondary,
              ),
            ),
            const SizedBox(height: GGSpacing.m - 4),
            GGStatusPill(
              label: online ? 'Live' : 'Offline',
              color: online ? GGColors.primary : GGColors.unknown,
              textColor: online ? GGColors.primaryDark : GGColors.textTertiary,
              container:
                  online ? GGColors.primaryContainer : GGColors.surfaceMuted,
              glowing: online,
            ),
          ],
        ),
      ),
    );
  }
}
