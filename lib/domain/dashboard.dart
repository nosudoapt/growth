import 'dart:convert';

/// Pull a JSON object out of a model's reply, tolerating code fences and
/// pre/postamble. Returns parsed Map or throws FormatException.
Map<String, dynamic> extractJsonObject(String raw) {
  var s = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true)
      .firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('No JSON object found in model reply');
  }
  s = s.substring(start, end + 1);
  // Normalize smart quotes that some models emit.
  s = s.replaceAll('\u201c', '"').replaceAll('\u201d', '"');
  final decoded = jsonDecode(s);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Model reply is not a JSON object');
  }
  return decoded;
}

/// ---- Strict validator for the dashboard schema. ----
/// Returns an empty list when v matches the schema, else the list of errors.
List<String> validateDashboard(Map<String, dynamic> m) {
  final e = <String>[];

  List<Map<String, dynamic>> listOfMaps(String key) {
    final v = m[key];
    if (v is! List) return const [];
    return v.whereType<Map<String, dynamic>>().toList();
  }

  final dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  for (final k in const ['focus_trend', 'mood_trend', 'time_well_spent_trend']) {
    if (!m.containsKey(k) || m[k] is! List) {
      e.add('"$k" missing or not a list');
      continue;
    }
    for (final item in listOfMaps(k)) {
      final d = item['date'];
      final val = item['value'];
      if (d is! String || !dateRe.hasMatch(d)) {
        e.add('"$k" date must be YYYY-MM-DD');
      }
      if (val is! num || val < 1 || val > 5) {
        e.add('"$k" value must be int in 1..5');
      }
    }
  }
  if (m['weekly_suggestion'] is! String) e.add('"weekly_suggestion" must be a string');

  final reading = m['reading'];
  if (reading is! Map<String, dynamic>) {
    e.add('"reading" must be an object');
  } else {
    if (reading['minutes_by_day'] is! List) {
      e.add('"reading.minutes_by_day" must be a list');
    }
    for (final d in (reading['minutes_by_day'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      if (d['date'] is! String || d['minutes'] is! num) {
        e.add('"reading.minutes_by_day" items need date + minutes');
      }
    }
    if (reading['streak'] is! num) e.add('"reading.streak" must be a number');
    if (reading['longest_streak'] is! num) {
      e.add('"reading.longest_streak" must be a number');
    }
    if (reading['finished_by_topic'] is! Map<String, dynamic>) {
      e.add('"reading.finished_by_topic" must be an object');
    }
  }

  final favoritesShape = m['favorites'];
  if (favoritesShape is! List) {
    e.add('"favorites" missing or not a list');
  }
  for (final f
      in ((m['favorites'] ?? const []) as List).whereType<Map<String, dynamic>>()) {
    if (f['name'] is! String || f['why'] is! String) {
      e.add('"favorites" items need name + why');
    }
    if (f['type'] is! String ||
        !const ['topic', 'source', 'author'].contains(f['type'])) {
      e.add('"favorites.type" must be topic|source|author');
    }
    if (f['likes'] is! num) e.add('"favorites.likes" must be a number');
  }

  for (final k in const ['good_habits', 'bad_habits']) {
    if (!m.containsKey(k) || m[k] is! List) {
      e.add('"$k" missing or not a list');
      continue;
    }
    for (final h in listOfMaps(k)) {
      if (h['name'] is! String) e.add('"$k" items need a name');
      if (k == 'good_habits' && h['consistency_pct'] is! num) {
        e.add('"good_habits.consistency_pct" must be a number');
      }
    }
    if (k == 'good_habits') {
      for (final h in listOfMaps(k)) {
        if (h['note'] is! String) e.add('"good_habits.note" must be a string');
      }
    } else {
      for (final h in listOfMaps(k)) {
        if (h['pattern'] is! String || h['gentle_alternative'] is! String) {
          e.add('"bad_habits" items need pattern + gentle_alternative');
        }
      }
    }
  }

  if (!m.containsKey('progress') || m['progress'] is! List) {
    e.add('"progress" missing or not a list');
  } else {
    for (final p in listOfMaps('progress')) {
      if (p['metric'] is! String ||
          p['this_week'] is! num ||
          p['last_week'] is! num ||
          p['note'] is! String) {
        e.add('"progress" items need metric, this_week, last_week, note');
      }
    }
  }
  if (m['win_of_the_week'] is! String) e.add('"win_of_the_week" must be a string');

  final nq = m['next_question'];
  if (nq != null && nq is! String) e.add('"next_question" must be string or null');

  return e;
}

/// Typed view over a validated dashboard JSON.
class DashboardData {
  DashboardData._(this.raw, this.updatedAt);

  final Map<String, dynamic> raw;
  final DateTime updatedAt;

  factory DashboardData.fromValidated(
    Map<String, dynamic> raw,
    DateTime updatedAt,
  ) {
    return DashboardData._(raw, updatedAt);
  }

  String get weeklySuggestion => (raw['weekly_suggestion'] ?? '') as String;
  String get winOfTheWeek => (raw['win_of_the_week'] ?? '') as String;
  String? get nextQuestion => raw['next_question'] as String?;

  List<List<double>> trends(String key, List<String> dates) {
    final out = <List<double>>[];
    final list = (raw[key] ?? const <dynamic>[]) as List;
    final perDate = <String, double>{};
    for (final item in list) {
      if (item is Map<String, dynamic> &&
          item['date'] is String &&
          item['value'] is num) {
        perDate[item['date'] as String] = (item['value'] as num).toDouble();
      }
    }
    out.add([for (final d in dates) perDate[d] ?? 0.0]);
    return out;
  }

  Map<String, dynamic> get reading =>
      (raw['reading'] ?? const {}) as Map<String, dynamic>;

  int get readingStreak => (reading['streak'] as num?)?.toInt() ?? 0;
  int get readingLongest => (reading['longest_streak'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get favorites =>
      ((raw['favorites'] ?? const <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .toList();

  List<Map<String, dynamic>> get goodHabits =>
      ((raw['good_habits'] ?? const <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .toList();

  List<Map<String, dynamic>> get badHabits =>
      ((raw['bad_habits'] ?? const <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .toList();

  List<Map<String, dynamic>> get progress =>
      ((raw['progress'] ?? const <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
}
