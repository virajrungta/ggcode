import 'package:flutter/material.dart';

import '../../../core/api/models.dart';
import '../../../design/glass.dart';
import '../../../design/tokens.dart';

/// One sensor reading with its acceptable band.
///
/// Uses [FauxGlassSurface], not [GlassSurface]: these appear four-up in a grid,
/// and four `BackdropFilter`s side by side is four `saveLayer`s per frame for a
/// difference nobody can see at this size.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.parameter});

  final HealthParameter parameter;

  static const _icons = {
    'soil_pct': Icons.water_drop_outlined,
    'temp_c': Icons.thermostat_rounded,
    'rh': Icons.cloud_outlined,
    'lux': Icons.wb_sunny_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final color = GGColors.statusColor(parameter.status);
    final unit = parameter.idealRange?.unit ?? '';
    final hasValue = parameter.value != null;

    return FauxGlassSurface(
      borderColor: parameter.status == 'good'
          ? GGColors.glassBorderTop
          : color.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(GGSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_icons[parameter.parameter] ?? Icons.help_outline,
                  size: 16, color: color),
              const SizedBox(width: GGSpacing.s),
              Expanded(
                child: Text(
                  parameter.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: GGColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GGSpacing.m),
          if (hasValue)
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: _format(parameter.value!, parameter.parameter),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: GGColors.textPrimary,
                      height: 1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: unit,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GGColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            const Text(
              '—',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: GGColors.textTertiary,
                height: 1,
              ),
            ),
          const SizedBox(height: GGSpacing.m),
          _BandIndicator(parameter: parameter, color: color),
        ],
      ),
    );
  }

  /// Lux runs to five figures; two decimals there is noise, whereas
  /// temperature genuinely moves in tenths.
  static String _format(double value, String parameter) {
    if (parameter == 'lux') return value.round().toString();
    if (value.abs() >= 100) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}

/// A thin track showing where the value sits inside its acceptable range,
/// with the ideal core highlighted.
class _BandIndicator extends StatelessWidget {
  const _BandIndicator({required this.parameter, required this.color});

  final HealthParameter parameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final range = parameter.idealRange;
    final position = parameter.normalised;

    if (range == null || position == null) {
      return const SizedBox(height: 4);
    }

    final span = range.max - range.min;
    final idealStart =
        ((range.idealMin ?? range.min) - range.min) / span;
    final idealEnd = ((range.idealMax ?? range.max) - range.min) / span;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 4,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Positioned(
                left: width * idealStart.clamp(0.0, 1.0),
                width: width * (idealEnd - idealStart).clamp(0.0, 1.0),
                top: 1,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: GGColors.volt.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: GGDuration.normal,
                curve: Curves.easeOutCubic,
                left: (width * position - 3).clamp(0.0, width - 6),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
