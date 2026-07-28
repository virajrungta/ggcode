import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/glass.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';
import 'widgets/health_ring.dart';
import 'widgets/metric_tile.dart';

class PotDetailScreen extends ConsumerWidget {
  const PotDetailScreen({super.key, required this.pot});

  final Pot pot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(potSnapshotProvider(pot.id));

    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(pot.name)),
        body: RefreshIndicator(
          backgroundColor: GGColors.surface,
          color: GGColors.volt,
          onRefresh: () async {
            ref.invalidate(potSnapshotProvider(pot.id));
            await ref.read(potSnapshotProvider(pot.id).future);
          },
          child: snapshot.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(children: [
              GGEmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Something went wrong',
                body: e.toString(),
              ),
            ]),
            data: (data) => _Content(pot: pot, snapshot: data),
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.pot, required this.snapshot});

  final Pot pot;
  final PotSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = snapshot.health;
    final status = health?.status ?? 'unknown';

    var i = 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, GGSpacing.s, 20, 120),
      children: [
        // The one real blur on this screen; everything below is faux glass.
        GlassSurface(
          blur: GGBlur.heavy,
          radius: GGRadius.xl,
          padding: const EdgeInsets.symmetric(
              vertical: GGSpacing.xl, horizontal: GGSpacing.l),
          glowColor: GGColors.statusColor(status),
          child: Column(
            children: [
              HealthRing(score: health?.score, status: status),
              const SizedBox(height: GGSpacing.l),
              Text(
                pot.species?.displayName ?? 'Unidentified plant',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: GGColors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              if (pot.species != null &&
                  pot.species!.commonName != pot.species!.scientificName) ...[
                const SizedBox(height: 2),
                Text(
                  pot.species!.scientificName,
                  style: const TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: GGColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: GGSpacing.m),
              _LiveBadge(snapshot: snapshot),
            ],
          ),
        ).entrance(index: i++),

        if (health != null && health.isGuess) ...[
          const SizedBox(height: GGSpacing.m),
          const _GuessBanner().entrance(index: i++),
        ],

        if (health != null) ...[
          const SizedBox(height: GGSpacing.xl),
          const GGSectionHeader(title: 'Conditions').entrance(index: i++),
          const SizedBox(height: GGSpacing.m),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: GGSpacing.m - 4,
            crossAxisSpacing: GGSpacing.m - 4,
            childAspectRatio: 1.28,
            children: [
              for (final p in health.parameters) MetricTile(parameter: p),
            ],
          ).entrance(index: i++),
        ],

        if (health != null && health.recommendations.isNotEmpty) ...[
          const SizedBox(height: GGSpacing.xl),
          const GGSectionHeader(title: 'What to do').entrance(index: i++),
          const SizedBox(height: GGSpacing.m),
          _Recommendations(items: health.recommendations).entrance(index: i++),
        ],

        if (health != null && health.notes.isNotEmpty) ...[
          const SizedBox(height: GGSpacing.m),
          _Notes(notes: health.notes).entrance(index: i++),
        ],

        if (pot.hasDevice) ...[
          const SizedBox(height: GGSpacing.xl),
          _WaterButton(potId: pot.id).entrance(index: i++),
        ],
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.snapshot});

  final PotSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final reading = snapshot.reading;
    final online = snapshot.online;

    final label = switch ((online, reading)) {
      (true, _) => 'Live',
      (false, final r?) => 'Last seen ${_ago(r.time)}',
      (false, null) => 'No data yet',
    };

    return GGStatusPill(
      label: label,
      color: online ? GGColors.volt : GGColors.textTertiary,
      glowing: online,
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Shown when thresholds came from the global default rather than a real
/// profile. The backend reports species/genus/default confidence precisely so
/// this can be surfaced instead of presenting a guess as fact.
class _GuessBanner extends StatelessWidget {
  const _GuessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GGSpacing.m),
      decoration: BoxDecoration(
        borderRadius: GGRadius.lAll,
        color: GGColors.amber.withValues(alpha: 0.08),
        border: Border.all(color: GGColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const GGIconTile(
              icon: Icons.info_rounded, color: GGColors.amber, size: 40,
              iconSize: 18),
          const SizedBox(width: GGSpacing.m - 4),
          const Expanded(
            child: Text(
              'Using general care ranges. Identify this plant for thresholds '
              'tuned to its species.',
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                color: GGColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Container(
            margin: const EdgeInsets.only(bottom: GGSpacing.s),
            padding: const EdgeInsets.all(GGSpacing.m),
            decoration: BoxDecoration(
              borderRadius: GGRadius.mAll,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
              border: Border.all(color: GGColors.glassBorderTop),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: GGColors.volt),
                const SizedBox(width: GGSpacing.m - 4),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: GGColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GGSpacing.m),
      decoration: BoxDecoration(
        borderRadius: GGRadius.mAll,
        color: GGColors.cyan.withValues(alpha: 0.06),
        border: Border.all(color: GGColors.cyan.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GGCaption('Good to know', color: GGColors.cyan),
          const SizedBox(height: GGSpacing.s),
          for (final note in notes)
            Text(
              note,
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                color: GGColors.textSecondary,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }
}

class _WaterButton extends ConsumerStatefulWidget {
  const _WaterButton({required this.potId});

  final String potId;

  @override
  ConsumerState<_WaterButton> createState() => _WaterButtonState();
}

class _WaterButtonState extends ConsumerState<_WaterButton> {
  bool _busy = false;

  Future<void> _water() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).water(widget.potId, durationSeconds: 5);
      if (mounted) _toast('Watering for 5 seconds', GGColors.volt);
      ref.invalidate(potSnapshotProvider(widget.potId));
    } on ApiException catch (e) {
      // The backend's refusals are written for humans — "Soil is already at
      // 88% moisture. Watering now risks root rot." — so show them verbatim
      // rather than flattening to a generic failure.
      if (mounted) _toast(e.message, e.isConflict ? GGColors.amber : GGColors.bad);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        shape: RoundedRectangleBorder(
          borderRadius: GGRadius.sAll,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: GGRadius.mAll,
        boxShadow: _busy ? null : ggGlow(GGColors.volt, opacity: 0.3),
      ),
      child: FilledButton.icon(
        onPressed: _busy ? null : _water,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: GGColors.bgDeep),
              )
            : const Icon(Icons.water_drop_rounded, size: 20),
        label: Text(_busy ? 'Watering…' : 'Water now'),
      ),
    );
  }
}
