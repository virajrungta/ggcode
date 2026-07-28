import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(pot.name),
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: GGColors.textPrimary,
          ),
          iconTheme: const IconThemeData(color: GGColors.textPrimary),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            backgroundColor: GGColors.surface,
            color: GGColors.volt,
            onRefresh: () async {
              ref.invalidate(potSnapshotProvider(pot.id));
              await ref.read(potSnapshotProvider(pot.id).future);
            },
            child: snapshot.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: GGColors.volt),
              ),
              error: (e, _) => _ErrorState(message: e.toString()),
              data: (data) => _Content(pot: pot, snapshot: data),
            ),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          GGSpacing.m, GGSpacing.s, GGSpacing.m, GGSpacing.xxl),
      children: [
        // The one real blur on this screen. Everything below is faux glass.
        GlassSurface(
          blur: GGBlur.heavy,
          padding: const EdgeInsets.symmetric(
              vertical: GGSpacing.xl, horizontal: GGSpacing.l),
          glowColor: health == null
              ? null
              : GGColors.statusColor(health.status),
          child: Column(
            children: [
              HealthRing(
                score: health?.score,
                status: health?.status ?? 'unknown',
              ),
              const SizedBox(height: GGSpacing.l),
              Text(
                pot.species?.displayName ?? 'Unidentified plant',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: GGColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GGSpacing.xs),
              _StatusLine(snapshot: snapshot),
            ],
          ),
        ),

        if (health != null && health.isGuess) ...[
          const SizedBox(height: GGSpacing.m),
          const _GuessBanner(),
        ],

        if (health != null) ...[
          const SizedBox(height: GGSpacing.l),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: GGSpacing.m,
            crossAxisSpacing: GGSpacing.m,
            childAspectRatio: 1.35,
            children: [
              for (final p in health.parameters) MetricTile(parameter: p),
            ],
          ),
        ],

        if (health != null && health.recommendations.isNotEmpty) ...[
          const SizedBox(height: GGSpacing.l),
          _Recommendations(items: health.recommendations),
        ],

        if (pot.hasDevice) ...[
          const SizedBox(height: GGSpacing.l),
          _WaterButton(potId: pot.id),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.snapshot});

  final PotSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final online = snapshot.online;
    final reading = snapshot.reading;

    final label = switch ((online, reading)) {
      (true, _) => 'Live',
      (false, final r?) => 'Last seen ${_ago(r.time)}',
      (false, null) => 'No data yet',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? GGColors.volt : GGColors.textTertiary,
            boxShadow: online
                ? [BoxShadow(color: GGColors.volt.withValues(alpha: 0.7), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: GGSpacing.s),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: GGColors.textSecondary),
        ),
      ],
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

/// Shown when the care thresholds came from the global default rather than a
/// real profile. The backend distinguishes species/genus/default confidence
/// precisely so this can be surfaced instead of presenting a guess as fact.
class _GuessBanner extends StatelessWidget {
  const _GuessBanner();

  @override
  Widget build(BuildContext context) {
    return FauxGlassSurface(
      borderColor: GGColors.amber.withValues(alpha: 0.35),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: GGColors.amber),
          const SizedBox(width: GGSpacing.m),
          const Expanded(
            child: Text(
              'Using general plant care ranges. Identify this plant for '
              'thresholds tuned to its species.',
              style: TextStyle(fontSize: 13, color: GGColors.textSecondary, height: 1.4),
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
    return FauxGlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHAT TO DO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: GGColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: GGSpacing.m),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: GGSpacing.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 7, right: GGSpacing.m),
                    decoration: const BoxDecoration(
                      color: GGColors.volt,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        color: GGColors.textPrimary,
                        height: 1.4,
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
        backgroundColor: GGColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GGRadius.m),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: _busy ? null : _water,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: GGColors.bgDeep),
              )
            : const Icon(Icons.water_drop_rounded, size: 20),
        label: Text(_busy ? 'Watering…' : 'Water now'),
        style: FilledButton.styleFrom(
          backgroundColor: GGColors.volt,
          foregroundColor: GGColors.bgDeep,
          disabledBackgroundColor: GGColors.volt.withValues(alpha: 0.4),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GGRadius.l),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(GGSpacing.xl),
      children: [
        const SizedBox(height: GGSpacing.xxl),
        const Icon(Icons.cloud_off_rounded, size: 48, color: GGColors.textTertiary),
        const SizedBox(height: GGSpacing.l),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GGColors.textSecondary, height: 1.5),
        ),
      ],
    );
  }
}
