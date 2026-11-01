import 'package:flutter_test/flutter_test.dart';
import 'package:growth/logic/streak.dart';

void main() {
  group('ReadingStreaks', () {
    Map<String, double> d(List<String> days) =>
        {for (final k in days) k: 10.0};

    test('consecutive days chain', () {
      final m = d(['2026-11-01', '2026-11-02']);
      expect(ReadingStreaks.current(m, todayIso: '2026-11-02'), 2);
      expect(ReadingStreaks.longest(m), 2);
    });

    test('gap breaks streaks in longest calc', () {
      final m = d(['2026-10-01', '2026-10-02', '2026-10-05', '2026-10-06']);
      expect(ReadingStreaks.longest(m), 2);
    });

    test('today not read yet: yesterday keeps streak alive', () {
      final m = d(['2026-10-30', '2026-10-31']);
      expect(
        ReadingStreaks.current(m, todayIso: '2026-11-01'),
        2,
        reason: 'parse handles month boundary',
      );
    });

    test('streak ends after a missed midnight', () {
      final m = d(['2026-10-29']);
      expect(ReadingStreaks.current(m, todayIso: '2026-11-01'), 0);
    });

    test('empty map is zero', () {
      expect(ReadingStreaks.current({}), 0);
      expect(ReadingStreaks.longest({}), 0);
    });

    test('zero-minute days do not count', () {
      final m = {'2026-11-01': 0.0, '2026-11-02': 4.2};
      expect(ReadingStreaks.longest(m), 1);
      expect(ReadingStreaks.current(m, todayIso: '2026-11-02'), 1);
    });
  });
}
