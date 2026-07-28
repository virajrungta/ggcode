import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';

enum _Metric {
  soil('Soil', 'soil_pct', '%', GGColors.cyan, Icons.water_drop_rounded),
  temp('Temp', 'temp_c', '°C', GGColors.amber, Icons.thermostat_rounded),
  humidity('Humidity', 'rh', '%', GGColors.magenta, Icons.cloud_rounded),
  light('Light', 'lux', 'lx', GGColors.volt, Icons.wb_sunny_rounded);

  const _Metric(this.label, this.key, this.unit, this.color, this.icon);

  final String label;
  final String key;
  final String unit;
  final Color color;
  final IconData icon;

  double? read(SeriesPoint p) => switch (this) {
        _Metric.soil => p.soilPct,
        _Metric.temp => p.tempC,
        _Metric.humidity => p.rh,
        _Metric.light => p.lux,
      };
}

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  _Metric _metric = _Metric.soil;
  String? _potId;

  @override
  Widget build(BuildContext context) {
    final pots = ref.watch(potsProvider);

    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: pots.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => GGEmptyState(
            icon: Icons.cloud_off_rounded,
            title: "Can't reach the server",
            body: e.toString(),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const GGEmptyState(
                icon: Icons.insights_rounded,
                title: 'No data yet',
                body: 'Pair a pot and its history will appear here.',
              );
            }
            final potId = _potId ?? list.first.id;
            final pot = list.firstWhere((p) => p.id == potId,
                orElse: () => list.first);

            return _Body(
              pots: list,
              pot: pot,
              metric: _metric,
              onPot: (id) => setState(() => _potId = id),
              onMetric: (m) => setState(() => _metric = m),
            );
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.pots,
    required this.pot,
    required this.metric,
    required this.onPot,
    required this.onMetric,
  });

  final List<Pot> pots;
  final Pot pot;
  final _Metric metric;
  final ValueChanged<String> onPot;
  final ValueChanged<_Metric> onMetric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(potSeriesProvider(pot.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        GGHeroHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last 48 hours',
                style: TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Trends',
                style: TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: GGColors.textPrimary,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
              if (pots.length > 1) ...[
                const SizedBox(height: GGSpacing.m),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: pots.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _Chip(
                      label: pots[i].name,
                      selected: pots[i].id == pot.id,
                      onTap: () => onPot(pots[i].id),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ).entrance(),
        const SizedBox(height: GGSpacing.l),
        Padding(
          padding: GGSpacing.page,
          child: _MetricSelector(selected: metric, onSelect: onMetric)
              .entrance(index: 1),
        ),
        const SizedBox(height: GGSpacing.l),
        Padding(
          padding: GGSpacing.page,
          child: series.when(
            loading: () => const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 240,
              child: Center(
                child: Text('$e',
                    style: const TextStyle(color: GGColors.textSecondary)),
              ),
            ),
            data: (points) => Column(
              children: [
                _ChartCard(points: points, metric: metric).entrance(index: 2),
                const SizedBox(height: GGSpacing.m),
                _StatsRow(points: points, metric: metric).entrance(index: 3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GGTappable(
      onTap: onTap,
      radius: GGRadius.round,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? GGColors.volt.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(GGRadius.round),
          border: Border.all(
            color: selected
                ? GGColors.volt.withValues(alpha: 0.5)
                : GGColors.glassBorderTop,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: kFontFamily,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? GGColors.volt : GGColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MetricSelector extends StatelessWidget {
  const _MetricSelector({required this.selected, required this.onSelect});

  final _Metric selected;
  final ValueChanged<_Metric> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GGColors.surface1,
        borderRadius: GGRadius.mAll,
        border: Border.all(color: GGColors.hairline),
      ),
      child: Row(
        children: [
          for (final m in _Metric.values)
            Expanded(
              child: GGTappable(
                onTap: () => onSelect(m),
                radius: GGRadius.s,
                child: AnimatedContainer(
                  duration: GGDuration.fast,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: m == selected
                        ? m.color.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: GGRadius.sAll,
                  ),
                  child: Column(
                    children: [
                      Icon(m.icon,
                          size: 18,
                          color: m == selected
                              ? m.color
                              : GGColors.textTertiary),
                      const SizedBox(height: 4),
                      Text(
                        m.label,
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 11,
                          fontWeight:
                              m == selected ? FontWeight.w700 : FontWeight.w500,
                          color:
                              m == selected ? m.color : GGColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.points, required this.metric});

  final List<SeriesPoint> points;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final values = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = metric.read(points[i]);
      // Gaps are skipped rather than zero-filled: drawing a missing hour as 0
      // would render a cliff to the floor and read as a real event.
      if (v != null) values.add(FlSpot(i.toDouble(), v));
    }

    if (values.length < 2) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GGColors.surface1,
          borderRadius: GGRadius.lAll,
          border: Border.all(color: GGColors.hairline),
        ),
        child: const Text(
          'Not enough data yet',
          style: TextStyle(
              fontFamily: kFontFamily, color: GGColors.textSecondary),
        ),
      );
    }

    final ys = values.map((s) => s.y).toList()..sort();
    final min = ys.first;
    final max = ys.last;
    final pad = (max - min) * 0.15 + 0.5;

    final latest = values.last.y;
    final first = values.first.y;
    final delta = latest - first;

    return Container(
      padding: const EdgeInsets.all(GGSpacing.l),
      decoration: BoxDecoration(
        color: GGColors.surface1,
        borderRadius: GGRadius.lAll,
        border: Border.all(color: GGColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GGCaption('Current ${metric.label}'),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        metric == _Metric.light
                            ? latest.round().toString()
                            : latest.toStringAsFixed(1),
                        style: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: GGColors.textPrimary,
                          letterSpacing: -1.5,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        metric.unit,
                        style: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: GGColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              _DeltaPill(delta: delta, unit: metric.unit, metric: metric),
            ],
          ),
          const SizedBox(height: GGSpacing.l),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: min - pad,
                maxY: max + pad,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ((max + pad) - (min - pad)) / 3,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: GGColors.hairline,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => GGColors.surface3,
                    tooltipRoundedRadius: 10,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(1)}${metric.unit}',
                              TextStyle(
                                fontFamily: kFontFamily,
                                color: metric.color,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: values,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    barWidth: 2.5,
                    color: metric.color,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          metric.color.withValues(alpha: 0.28),
                          metric.color.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: GGSpacing.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GGCaption('48h ago'),
              GGCaption('now'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({
    required this.delta,
    required this.unit,
    required this.metric,
  });

  final double delta;
  final String unit;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final rising = delta >= 0;
    // Neutral colouring: a rising value is not inherently good or bad — more
    // soil moisture is good, more heat may not be — so this reports direction
    // only and leaves the judgement to the health engine.
    const color = GGColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: GGColors.surface3,
        borderRadius: BorderRadius.circular(GGRadius.round),
        border: Border.all(color: GGColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rising ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            '${rising ? '+' : ''}'
            '${metric == _Metric.light ? delta.round() : delta.toStringAsFixed(1)}'
            '$unit',
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}


/// Min / average / max over the window.
///
/// The chart shows shape; these show magnitude. Together they answer "is this
/// normal for this plant" in a way neither does alone.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.points, required this.metric});

  final List<SeriesPoint> points;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final values = points.map(metric.read).whereType<double>().toList();
    if (values.isEmpty) return const SizedBox.shrink();

    final sorted = [...values]..sort();
    final min = sorted.first;
    final max = sorted.last;
    final avg = values.reduce((a, b) => a + b) / values.length;

    String fmt(double v) =>
        metric == _Metric.light ? v.round().toString() : v.toStringAsFixed(1);

    return Row(
      children: [
        Expanded(child: _Stat(label: 'Low', value: fmt(min), unit: metric.unit)),
        const SizedBox(width: GGSpacing.m - 4),
        Expanded(
          child: _Stat(
            label: 'Average',
            value: fmt(avg),
            unit: metric.unit,
            accent: metric.color,
          ),
        ),
        const SizedBox(width: GGSpacing.m - 4),
        Expanded(child: _Stat(label: 'High', value: fmt(max), unit: metric.unit)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    this.accent,
  });

  final String label;
  final String value;
  final String unit;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: GGSpacing.m, horizontal: GGSpacing.s + 2),
      decoration: BoxDecoration(
        color: GGColors.surface1,
        borderRadius: GGRadius.mAll,
        border: Border.all(
          color: accent?.withValues(alpha: 0.3) ?? GGColors.hairline,
        ),
      ),
      child: Column(
        children: [
          GGCaption(label),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accent ?? GGColors.textPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                Text(
                  unit,
                  style: const TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GGColors.textSecondary,
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
