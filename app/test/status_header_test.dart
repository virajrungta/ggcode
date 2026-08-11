import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greengenius/core/api/models.dart';
import 'package:greengenius/core/providers.dart';
import 'package:greengenius/design/tokens.dart';
import 'package:greengenius/features/dashboard/widgets/status_header.dart';

/// The header is the one thing on screen that has to survive a three-second
/// glance, so it is worth testing that it renders rather than assuming.
///
/// Layout overflow is the specific failure being hunted: the expanded header
/// stacks an eyebrow, a headline that may wrap to two lines at 26px, and a
/// detail line into a fixed 178px, and the analyzer cannot see that.

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
        score: 80,
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

Widget _harness({
  required List<Pot> pots,
  required Map<String, PotSnapshot> snapshots,
}) {
  return ProviderScope(
    overrides: [
      for (final entry in snapshots.entries)
        potSnapshotProvider(entry.key).overrideWith((ref) async => entry.value),
    ],
    child: MaterialApp(
      theme: GGTheme.light,
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            StatusHeader(pots: pots),
            const SliverToBoxAdapter(child: SizedBox(height: 1200)),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a healthy single pot without overflowing',
      (tester) async {
    final pot = _pot('p1', 'Monstera');
    await tester.pumpWidget(_harness(
      pots: [pot],
      snapshots: {
        'p1': _snapshot(
            potId: 'p1', status: 'good', message: 'Soil is right', value: 50),
      },
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Monstera'), findsWidgets);
    expect(find.text('ALL GOOD'), findsOneWidget);
  });

  testWidgets('a long care-engine message must not overflow the header',
      (tester) async {
    // The care engine writes full sentences, and this is the longest shape it
    // realistically produces. It wraps to two lines at the expanded size.
    final pot = _pot('p1', 'Fiddle Leaf Fig');
    await tester.pumpWidget(_harness(
      pots: [pot],
      snapshots: {
        'p1': _snapshot(
          potId: 'p1',
          status: 'bad',
          message: 'Soil is very dry at 12% — water thoroughly today to avoid '
              'root damage and leaf drop',
          value: 12,
        ),
      },
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
  });

  testWidgets('reports the worst pot, not an average', (tester) async {
    final a = _pot('p1', 'Happy Plant');
    final b = _pot('p2', 'Thirsty Plant');
    await tester.pumpWidget(_harness(
      pots: [a, b],
      snapshots: {
        'p1': _snapshot(
            potId: 'p1', status: 'good', message: 'Soil is right', value: 50),
        'p2': _snapshot(
            potId: 'p2', status: 'bad', message: 'Soil is dry', value: 10),
      },
    ));
    await tester.pumpAndSettle();

    // Averaging would have reported "all good" and hidden the dying plant.
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.textContaining('Thirsty Plant'), findsWidgets);
  });

  testWidgets('an unplugged probe is not reported as an unwell plant',
      (tester) async {
    final pot = _pot('p1', 'Monstera');
    await tester.pumpWidget(_harness(
      pots: [pot],
      snapshots: {
        'p1': _snapshot(
          potId: 'p1',
          status: 'unknown',
          message: 'No soil reading',
          value: null,
        ),
      },
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // An unplugged probe is a hardware problem, not a sick plant, so it must
    // not raise an alarm. See _unknownOnly for the other half of this: it must
    // not claim everything is fine either.
    expect(find.text('NEEDS ATTENTION'), findsNothing);
  });

  _unknownOnly();

  testWidgets('collapses without overflowing when scrolled', (tester) async {
    final pot = _pot('p1', 'Fiddle Leaf Fig');
    await tester.pumpWidget(_harness(
      pots: [pot],
      snapshots: {
        'p1': _snapshot(
          potId: 'p1',
          status: 'warning',
          message: 'Soil is drying out — water within a day or two',
          value: 32,
        ),
      },
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

/// Regression: the first version of `summarise` skipped 'unknown' parameters
/// when ranking, then fell through to the "nothing bad found" branch — so a
/// pot with every probe unplugged reported a confident green "is thriving".
/// That is worse than saying nothing, because it looks like an answer.
void _unknownOnly() {
  testWidgets('a pot with no usable readings does not claim to be thriving',
      (tester) async {
    final pot = _pot('p1', 'Monstera');
    await tester.pumpWidget(_harness(
      pots: [pot],
      snapshots: {
        'p1': _snapshot(
          potId: 'p1',
          status: 'unknown',
          message: 'No soil reading',
          value: null,
        ),
      },
    ));
    await tester.pumpAndSettle();

    expect(find.text('ALL GOOD'), findsNothing);
    expect(find.textContaining('thriving'), findsNothing);
    expect(find.text('WAITING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
