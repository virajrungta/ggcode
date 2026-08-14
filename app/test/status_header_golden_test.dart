@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greengenius/core/api/models.dart';
import 'package:greengenius/core/providers.dart';
import 'package:greengenius/design/tokens.dart';
import 'package:greengenius/features/dashboard/widgets/status_header.dart';

/// Renders the header to PNG so it can actually be looked at.
///
/// Written because the first two versions of this header shipped to a device
/// without anyone seeing them, and both were visibly broken in ways no
/// assertion caught: type drawn at 1.5x by `FlexibleSpaceBar`'s
/// `expandedTitleScale`, an eyebrow thrown into the status bar, and the empty
/// state printed three times on one screen. A passing widget test says the
/// widget built; it does not say it looks right.
///
/// Regenerate with:
///   flutter test test/status_header_golden_test.dart --update-goldens
///
/// The real font is loaded rather than the test default, which renders as
/// blank boxes — useless for judging type size, which is exactly what was
/// wrong before.

Future<void> _loadFonts() async {
  final app = FontLoader('PlusJakartaSans')
    ..addFont(
      File('assets/fonts/PlusJakartaSans-VariableFont.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)),
    );
  await app.load();

  // Without this every Icon draws as an empty square, which hides exactly the
  // element the header relies on to carry status non-visually.
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/src/flutter'}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

Pot _pot(String id, String name) => Pot(
      id: id,
      name: name,
      deviceId: 'dev-$id',
      autoWaterEnabled: false,
      autoWaterThresholdPct: 30,
    );

PotSnapshot _snapshot({
  required String potId,
  required String status,
  required String message,
  double? value,
}) =>
    PotSnapshot(
      potId: potId,
      deviceId: 'dev-$potId',
      online: true,
      reading: Reading(
        time: DateTime.now().subtract(const Duration(minutes: 4)),
        soilPct: value,
        flags: 0,
      ),
      health: Health(
        status: status,
        confidence: 'species',
        profileSource: 'species',
        parameters: [
          HealthParameter(
            parameter: 'soil_pct',
            label: 'Soil',
            status: status,
            message: message,
            value: value,
            idealRange: const IdealRange(
                min: 40, max: 60, idealMin: 45, idealMax: 55, unit: '%'),
          ),
        ],
        issues: const [],
        recommendations: const [],
        notes: const [],
      ),
    );

/// Header plus a slab of body, so the header is judged in context rather than
/// floating on its own.
Widget _screen({
  required List<Pot> pots,
  required Map<String, PotSnapshot> snapshots,
}) {
  return ProviderScope(
    overrides: [
      for (final e in snapshots.entries)
        potSnapshotProvider(e.key).overrideWith((ref) async => e.value),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: GGTheme.light,
      home: MediaQuery(
        // iPhone 17 Pro top inset. The header sizes itself off this, so a
        // golden without it is not a likeness of the device.
        data: const MediaQueryData(padding: EdgeInsets.only(top: 59)),
        child: Scaffold(
        backgroundColor: GGColors.bg,
        body: CustomScrollView(
          slivers: [
            StatusHeader(pots: pots),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    // Enough to make the list actually scrollable. With three
                    // cards the content was shorter than the viewport, so the
                    // "collapsed" golden silently rendered the expanded state.
                    for (var i = 0; i < 10; i++)
                      Container(
                        height: 92,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: GGColors.surface,
                          borderRadius: GGRadius.lAll,
                          boxShadow: ggCardShadow,
                        ),
                      ),
                  ],
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget widget, {
    double scrollBy = 0,
  }) async {
    // iPhone 17 Pro logical size, so the result is comparable to a device
    // screenshot rather than to an arbitrary test window.
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    if (scrollBy != 0) {
      await tester.drag(find.byType(CustomScrollView), Offset(0, -scrollBy));
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('empty', (tester) async {
    await shoot(tester, 'header_empty', _screen(pots: const [], snapshots: {}));
  });

  testWidgets('healthy', (tester) async {
    await shoot(
      tester,
      'header_healthy',
      _screen(pots: [_pot('p1', 'Monstera')], snapshots: {
        'p1': _snapshot(
            potId: 'p1', status: 'good', message: 'Soil is right', value: 50),
      }),
    );
  });

  testWidgets('needs water, long message', (tester) async {
    await shoot(
      tester,
      'header_needs_water',
      _screen(pots: [_pot('p1', 'Fiddle Leaf Fig')], snapshots: {
        'p1': _snapshot(
          potId: 'p1',
          status: 'bad',
          message: 'Soil is very dry at 12% — water thoroughly today to avoid '
              'root damage',
          value: 12,
        ),
      }),
    );
  });

  testWidgets('no sensor data — the bench pot right now', (tester) async {
    await shoot(
      tester,
      'header_no_data',
      _screen(pots: [_pot('p1', "Viraj's Tomato 1")], snapshots: {
        'p1': _snapshot(
            potId: 'p1', status: 'unknown', message: 'No soil reading'),
      }),
    );
  });

  testWidgets('collapsed', (tester) async {
    await shoot(
      tester,
      'header_collapsed',
      _screen(pots: [_pot('p1', 'Fiddle Leaf Fig')], snapshots: {
        'p1': _snapshot(
          potId: 'p1',
          status: 'warning',
          message: 'Soil is drying out — water within a day',
          value: 32,
        ),
      }),
      scrollBy: 200,
    );
  });
}
