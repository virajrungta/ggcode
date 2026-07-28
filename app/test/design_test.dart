import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greengenius/core/api/models.dart';
import 'package:greengenius/design/glass.dart';
import 'package:greengenius/design/mesh_background.dart';
import 'package:greengenius/design/tokens.dart';
import 'package:greengenius/features/dashboard/widgets/health_ring.dart';
import 'package:greengenius/features/dashboard/widgets/metric_tile.dart';
import 'package:greengenius/main.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('HealthRing', () {
    testWidgets('shows the score when one exists', (tester) async {
      await tester.pumpWidget(wrap(const HealthRing(score: 87, status: 'good')));
      await tester.pumpAndSettle();

      expect(find.text('87'), findsOneWidget);
      expect(find.text('GOOD'), findsOneWidget);
    });

    testWidgets('a null score reads as NO DATA, not as zero', (tester) async {
      // The distinction the whole null-score path exists for: "this plant is
      // dying" and "the sensor is offline" must not look the same.
      await tester.pumpWidget(
          wrap(const HealthRing(score: null, status: 'unknown')));
      await tester.pumpAndSettle();

      expect(find.text('NO DATA'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders each status without error', (tester) async {
      for (final status in ['good', 'warning', 'bad', 'unknown']) {
        await tester.pumpWidget(wrap(HealthRing(score: 50, status: status)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('MetricTile', () {
    HealthParameter param({
      double? value,
      String status = 'good',
      IdealRange? range,
    }) =>
        HealthParameter(
          parameter: 'soil_pct',
          label: 'Soil Moisture',
          status: status,
          message: 'ok',
          value: value,
          idealRange: range ??
              const IdealRange(
                  min: 25, max: 70, idealMin: 40, idealMax: 60, unit: '%'),
        );

    testWidgets('renders value with unit', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 180,
        child: MetricTile(parameter: param(value: 45.3)),
      )));
      await tester.pumpAndSettle();

      // Value and unit are spans of one RichText, so the plain text is joined
      // and the finder has to be told to descend into it.
      expect(find.text('45.3%', findRichText: true), findsOneWidget);
    });

    testWidgets('missing value shows a dash, not 0', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 180,
        child: MetricTile(parameter: param(value: null)),
      )));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('large lux values drop the decimal', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 180,
        child: MetricTile(
          parameter: HealthParameter(
            parameter: 'lux',
            label: 'Light',
            status: 'good',
            message: 'ok',
            value: 12345.67,
            idealRange: const IdealRange(min: 0, max: 50000, unit: 'lx'),
          ),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('12346lx', findRichText: true), findsOneWidget);
    });
  });

  group('HealthParameter.normalised', () {
    const range = IdealRange(min: 0, max: 100, idealMin: 40, idealMax: 60);

    HealthParameter at(double? v) => HealthParameter(
          parameter: 'soil_pct',
          label: 'Soil',
          status: 'good',
          message: '',
          value: v,
          idealRange: range,
        );

    test('maps value into 0..1 across the band', () {
      expect(at(50).normalised, closeTo(0.5, 1e-9));
      expect(at(0).normalised, 0.0);
      expect(at(100).normalised, 1.0);
    });

    test('clamps out-of-band values so the marker stays on the track', () {
      expect(at(-20).normalised, 0.0);
      expect(at(150).normalised, 1.0);
    });

    test('null without a value or range', () {
      expect(at(null).normalised, isNull);
      expect(
        const HealthParameter(
          parameter: 'x', label: 'X', status: 'unknown',
          message: '', value: 5, idealRange: null,
        ).normalised,
        isNull,
      );
    });
  });

  group('glass surfaces', () {
    testWidgets('GlassSurface applies a BackdropFilter when enabled',
        (tester) async {
      await tester.pumpWidget(wrap(
        const GlassSurface(child: Text('hi')),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('GlassSurface skips the blur when disabled', (tester) async {
      await tester.pumpWidget(wrap(
        const GlassSurface(enabled: false, child: Text('hi')),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('FauxGlassSurface never blurs — it is the list-safe variant',
        (tester) async {
      await tester.pumpWidget(wrap(
        const FauxGlassSurface(child: Text('hi')),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('GlassSurface is isolated behind a RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(wrap(const GlassSurface(child: Text('hi'))));
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });

  group('MeshBackground', () {
    testWidgets('renders children and can run without animation',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const MeshBackground(animate: false, child: Text('content')),
      ));
      await tester.pump();

      expect(find.text('content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('animating background settles without leaking a ticker',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MeshBackground(child: Text('content')),
      ));
      await tester.pump(const Duration(seconds: 1));

      // Replacing the tree disposes the controller; a leaked ticker throws here.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });

  group('status colours', () {
    test('map to the palette', () {
      expect(GGColors.statusColor('good'), GGColors.volt);
      expect(GGColors.statusColor('warning'), GGColors.amber);
      expect(GGColors.statusColor('bad'), GGColors.magenta);
      expect(GGColors.statusColor('anything-else'), GGColors.unknown);
    });
  });
}
