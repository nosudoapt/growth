import 'dart:math' as math;

/// Rotation helpers: cycle through a bank without repeats within a window.
///
/// - Thought bank: no repeat within the last 30 days.
/// - Check-in questions: no repeat within the last 14 days.
class Rotation {
  const Rotation._();

  /// Pick the next index in `bankLength` that is not in the recent set.
  /// If every index is used up, start a fresh cycle.
  static int nextIndex(int bankLength, Set<int> recent, {math.Random? rng}) {
    if (bankLength <= 0) return 0;
    final candidates = <int>[
      for (var i = 0; i < bankLength; i++)
        if (!recent.contains(i)) i,
    ];
    if (bankLength == 1) return 0;
    final r = rng ?? math.Random();
    if (candidates.isEmpty) {
      return r.nextInt(bankLength);
    }
    return candidates[r.nextInt(candidates.length)];
  }

  /// Recent indices within `windowDays`, given "date → index" history.
  /// Deterministic, order-independent, and testable.
  static Set<int> recentSince(
    List<(String, int)> history, // (date 'YYYY-MM-DD', index)
    int windowDays,
    DateTime today,
  ) {
    final result = <int>{};
    for (final (date, idx) in history) {
      final used = DateTime.tryParse(date);
      if (used == null) continue;
      final delta = today.difference(used).inDays;
      if (delta < windowDays) result.add(idx);
    }
    return result;
  }
}
