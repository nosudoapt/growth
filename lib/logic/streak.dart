/// Reading-streak calculations. Pure functions so they are unit-testable.
///
/// `dayMinutes` maps "YYYY-MM-DD" → minutes read that day (>0 counts as a day).
class ReadingStreaks {
  const ReadingStreaks._();

  static List<String> _sortedKeys(Map<String, double> dayMinutes) {
    final keys =
        dayMinutes.entries.where((e) => e.value > 0).map((e) => e.key).toList()
          ..sort();
    return keys;
  }

  static DateTime _parse(String ymd) {
    final parts = ymd.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  /// Current streak as of today, counting a zero-reading *today* as still
  /// intact only if yesterday was read (you get until midnight).
  static int current(Map<String, double> dayMinutes, {String? todayIso}) {
    final days = _sortedKeys(dayMinutes);
    if (days.isEmpty) return 0;
    final today = _parse(todayIso ?? _todayIso());
    final asSet = days.toSet();

    var streak = 0;
    var cursor = today;
    if (!asSet.contains(_iso(cursor))) {
      cursor = today.subtract(const Duration(days: 1));
      if (!asSet.contains(_iso(cursor))) return 0;
    }
    while (asSet.contains(_iso(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int longest(Map<String, double> dayMinutes) {
    final days = _sortedKeys(dayMinutes);
    if (days.isEmpty) return 0;
    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      final prev = _parse(days[i - 1]);
      final cur = _parse(days[i]);
      final gap =
          cur.difference(prev).inHours; // handles DST-free day difference
      if (gap <= 24) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
    }
    return best;
  }

  static String _todayIso() => _iso(DateTime.now());

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
