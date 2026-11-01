import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:growth/logic/rotation.dart';

void main() {
  group('Rotation', () {
    test('never repeats within the recent window with a seeded rng', () {
      final history = [
        for (var i = 0; i < 14; i++) ('2026-10-19', i),
      ];
      final recent =
          Rotation.recentSince(history, 14, DateTime(2026, 11, 2));
      for (var attempt = 0; attempt < 50; attempt++) {
        final next =
            Rotation.nextIndex(30, recent, rng: math.Random(attempt));
        expect(recent.contains(next), isFalse,
            reason: 'must avoid the last 14 days (pick was $next)');
      }
    });

    test('repeats (fresh cycle) when the entire bank is used up', () {
      final all = {for (var i = 0; i < 30; i++) i};
      final next = Rotation.nextIndex(30, all);
      expect(next, inInclusiveRange(0, 29));
    });

    test('single-item bank is safe', () {
      expect(Rotation.nextIndex(1, {}), 0);
      expect(Rotation.nextIndex(1, {0}), 0);
    });

    test('recentSince drops history older than the window', () {
      final history = [('2026-06-01', 3), ('2026-11-01', 5)];
      final recent =
          Rotation.recentSince(history, 14, DateTime(2026, 11, 2));
      expect(recent.contains(3), isFalse);
      expect(recent.contains(5), isTrue);
    });

    test('seeded rng is deterministic', () {
      final recent = {1, 2};
      final a = Rotation.nextIndex(10, recent, rng: math.Random(2));
      final b = Rotation.nextIndex(10, recent, rng: math.Random(2));
      expect(a, b);
      expect(recent.contains(a), isFalse);
    });

    test('question rotation window is 14 days and thought window 30', () {
      final old = [('2026-10-10', 7)];
      final qRecent =
          Rotation.recentSince(old, 14, DateTime(2026, 11, 2));
      final tRecent =
          Rotation.recentSince(old, 30, DateTime(2026, 11, 2));
      expect(qRecent.contains(7), isFalse, reason: 'older than 14 days');
      expect(tRecent.contains(7), isTrue, reason: 'within 30 days');
    });
  });
}
