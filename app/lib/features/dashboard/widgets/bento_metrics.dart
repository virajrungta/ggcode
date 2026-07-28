import 'package:flutter/material.dart';

import '../../../core/api/models.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';
import 'sparkline.dart';

/// Bento grid of the four sensor readings.
///
/// Asymmetric on purpose. A uniform 2x2 grid says all four metrics matter
/// equally; for a plant pot they do not. Soil moisture is the one that
/// actually decides whether the plant lives, so it takes a tall tile with a
/// trend line, and the other three sit beside and under it.
///
///     +-----------+-----------+
///     |           |   temp    |
///     |   soil    +-----------+
///     |  (trend)  | humidity  |
///     +-----------+-----------+
///     |         light         |
///     +-----------------------+
///
/// Gutters are one value everywhere — uneven gaps are what make a modular
/// grid read as accidental rather than designed.
class BentoMetrics extends StatelessWidget {
  const BentoMetrics({
    super.key,
    required this.parameters,
    this.soilHistory = const [],
    this.lightHistory = const [],
  });

  final List<HealthParameter> parameters;
  final List<double> soilHistory;
  final List<double> lightHistory;

  static const _gutter = 12.0;

  HealthParameter? _find(String key) {
    for (final p in parameters) {
      if (p.parameter == key) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final soil = _find('soil_pct');
    final temp = _find('temp_c');
    final rh = _find('rh');
    final lux = _find('lux');

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _FeatureTile(
                  parameter: soil,
                  label: 'Soil moisture',
                  icon: Icons.water_drop_rounded,
                  accent: GGColors.soil,
                  accentText: GGColors.soilText,
                  history: soilHistory,
                ),
              ),
              const SizedBox(width: _gutter),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _SmallTile(
                        parameter: temp,
                        label: 'Temp',
                        icon: Icons.thermostat_rounded,
                        accent: GGColors.temp,
                      ),
                    ),
                    const SizedBox(height: _gutter),
                    Expanded(
                      child: _SmallTile(
                        parameter: rh,
                        label: 'Humidity',
                        icon: Icons.cloud_rounded,
                        accent: GGColors.humidity,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _gutter),
        _WideTile(
          parameter: lux,
          label: 'Light',
          icon: Icons.wb_sunny_rounded,
          accent: GGColors.light,
          history: lightHistory,
        ),
      ],
    );
  }
}

/// Shared shell so every tile agrees on radius, border, and shadow.
class _TileShell extends StatelessWidget {
  const _TileShell({required this.child, required this.status});

  final Widget child;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GGSpacing.m),
      decoration: BoxDecoration(
        color: GGColors.surface,
        borderRadius: GGRadius.lAll,
        border: Border.all(
          color: status == 'good' || status == 'unknown'
              ? GGColors.outline
              : GGColors.statusColor(status).withValues(alpha: 0.45),
        ),
        boxShadow: ggCardShadow,
      ),
      child: child,
    );
  }
}

String _fmt(double v, String key) {
  if (key == 'lux') return v.round().toString();
  if (v.abs() >= 100) return v.round().toString();
  return v.toStringAsFixed(1);
}

Widget _value(HealthParameter? p, {double size = 30}) {
  if (p?.value == null) {
    return Text(
      '—',
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: GGColors.textTertiary,
        height: 1,
      ),
    );
  }
  return RichText(
    text: TextSpan(children: [
      TextSpan(
        text: _fmt(p!.value!, p.parameter),
        style: TextStyle(
          fontFamily: kFontFamily,
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: GGColors.textPrimary,
          height: 1,
          letterSpacing: -1.2,
        ),
      ),
      TextSpan(
        text: p.idealRange?.unit ?? '',
        style: TextStyle(
          fontFamily: kFontFamily,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: GGColors.textSecondary,
        ),
      ),
    ]),
  );
}

/// The tall tile. Carries a trend line, because the metric it shows is the one
/// worth watching over time rather than just reading now.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.parameter,
    required this.label,
    required this.icon,
    required this.accent,
    required this.accentText,
    required this.history,
  });

  final HealthParameter? parameter;
  final String label;
  final IconData icon;
  final Color accent;
  final Color accentText;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final status = parameter?.status ?? 'unknown';

    return _TileShell(
      status: status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GGIconTile(icon: icon, color: accent, size: 32, iconSize: 16),
              const SizedBox(width: GGSpacing.s),
              Expanded(child: GGCaption(label)),
            ],
          ),
          const SizedBox(height: GGSpacing.m),
          _value(parameter, size: 34),
          if (parameter?.idealRange != null) ...[
            const SizedBox(height: 4),
            Text(
              'ideal ${_fmt(parameter!.idealRange!.idealMin ?? parameter!.idealRange!.min, parameter!.parameter)}'
              '–${_fmt(parameter!.idealRange!.idealMax ?? parameter!.idealRange!.max, parameter!.parameter)}'
              '${parameter!.idealRange!.unit}',
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: GGColors.textTertiary,
              ),
            ),
          ],
          const Spacer(),
          if (history.length >= 2)
            SizedBox(
              height: 44,
              width: double.infinity,
              child: Sparkline(values: history, color: accent),
            ),
        ],
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({
    required this.parameter,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final HealthParameter? parameter;
  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final status = parameter?.status ?? 'unknown';

    return _TileShell(
      status: status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Expanded(child: GGCaption(label)),
            ],
          ),
          FittedBox(fit: BoxFit.scaleDown, child: _value(parameter, size: 26)),
        ],
      ),
    );
  }
}

class _WideTile extends StatelessWidget {
  const _WideTile({
    required this.parameter,
    required this.label,
    required this.icon,
    required this.accent,
    required this.history,
  });

  final HealthParameter? parameter;
  final String label;
  final IconData icon;
  final Color accent;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final status = parameter?.status ?? 'unknown';

    return _TileShell(
      status: status,
      child: Row(
        children: [
          GGIconTile(icon: icon, color: accent, size: 36, iconSize: 18),
          const SizedBox(width: GGSpacing.m - 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GGCaption(label),
              const SizedBox(height: 4),
              _value(parameter, size: 24),
            ],
          ),
          const SizedBox(width: GGSpacing.m),
          if (history.length >= 2)
            Expanded(
              child: SizedBox(
                height: 38,
                child: Sparkline(values: history, color: accent),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }
}
