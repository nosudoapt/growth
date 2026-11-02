import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/db.dart';
import '../repos/checkins.dart';
import '../repos/dashboard.dart';
import '../repos/evals.dart';
import '../repos/library.dart';

/// Weekly Sunday summary (plain text) + full JSON export. The API key is
/// never included in either — it lives only in secure storage and is read
/// into memory only at LLM call time.
class Exports {
  const Exports._();

  static Future<void> shareWeeklySummary() async {
    final text = await weeklySummaryText();
    await SharePlus.instance.share(ShareParams(text: text));
    await Db.kvSet('last_export_week', weekStamp());
  }

  static Future<String> weeklySummaryText() async {
    final buf = StringBuffer('Growth — this week\n\n');
    // Ratings: average sliders over the last 7 days.
    final nightly = await CheckinRepo.lastNights(7);
    if (nightly.isNotEmpty) {
      double avg(String k) {
        final vals = [
          for (final c in nightly) (c[k] as num?)?.toDouble() ?? 0.0
        ].where((v) => v > 0).toList();
        if (vals.isEmpty) return 0.0;
        return vals.reduce((a, b) => a + b) / vals.length;
      }

      buf.writeln('Mood (avg): ${avg('mood').toStringAsFixed(1)}/5');
      buf.writeln('Focus (avg): ${avg('focus').toStringAsFixed(1)}/5');
      buf.writeln(
          'Time well spent (avg): ${avg('time_well_spent').toStringAsFixed(1)}/5');
    } else {
      buf.writeln('No check-ins recorded yet this week.');
    }

    // Top likes and skips.
    final likes = await _countByKind('like');
    buf.writeln('\nMost liked:');
    for (final e in likes.take(3)) {
      buf.writeln('- ${e.key} (${e.value})');
    }
    final skips = await _countByKind('skip');
    if (skips.isNotEmpty) {
      buf.writeln('Skipped:');
      for (final e in skips.take(3)) {
        buf.writeln('- ${e.key} (${e.value})');
      }
    }

    // Dashboard highlights.
    final dash = await DashboardRepo.current();
    if (dash != null) {
      final s = dash.weeklySuggestion.trim();
      final w = dash.winOfTheWeek.trim();
      if (w.isNotEmpty) buf.writeln('\nWin of the week: $w');
      if (s.isNotEmpty) buf.writeln('Suggestion: $s');
      buf.writeln('Reading streak: ${dash.readingStreak} day(s), longest ${dash.readingLongest}.');
    }

    // Reading minutes.
    final minutes = await LibraryRepo.minutesByDay(days: 7);
    final total = minutes.values.fold(0.0, (a, b) => a + b);
    buf.writeln('\nReading this week: ${total.toStringAsFixed(0)} min.');

    // Latest eval score.
    final runs = await EvalRepo.runs();
    if (runs.isNotEmpty) {
      final r = runs.first;
      buf.writeln(
          'Eval agreement: ${(((r['agreement_pct'] as num?) ?? 0) * 100).toStringAsFixed(0)}% '
          '(${r['prompt_version']}).');
    }
    return buf.toString();  }

  static Future<List<MapEntry<String, int>>> _countByKind(String kind) async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        "SELECT item_key, COUNT(*) AS c FROM interactions WHERE kind = ? "
        "AND ts > ? GROUP BY item_key ORDER BY c DESC LIMIT 10",
        [kind, DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch]);
    return [
      for (final r in rows)
        MapEntry((r['item_key'] as String).split('#').last, r['c'] as int),
    ];
  }

  /// Export everything as JSON (no API key, by construction).
  static Future<void> shareAllData() async {
    final db = await Db.instance();
    final out = <String, dynamic>{};
    const tables = [
      'reads', 'interactions', 'checkins', 'question_history',
      'thought_days', 'reading_time', 'dashboards', 'eval_items',
      'eval_runs', 'token_usage', 'profile', 'kv',
    ];
    for (final t in tables) {
      final rows = await db.query(t);
      out[t] = rows;
    }
    final json = const JsonEncoder.withIndent('  ').convert(out);
    final dir = await getApplicationDocumentsDirectory();
    final f = dir
        .childFile('growth_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await f.writeAsString(json);
    await SharePlus.instance.share(ShareParams(
      text: 'Growth data export (no API key included).',
      files: [XFile(f.path)],
    ));
  }

  /// Everything wiped. Called from Settings with a confirm dialog.
  static Future<void> deleteAll() async {
    await Db.wipe();
  }
}

String weekStamp() {
  final n = DateTime.now();
  final sunday = n.subtract(Duration(days: n.weekday % 7));
  return '${sunday.year}-${sunday.month}-${sunday.day}';
}

/// Used by the root widget to decide whether to prompt the weekly share.
Future<bool> shouldOfferWeeklyExport() async {
  final now = DateTime.now();
  return now.weekday == DateTime.sunday &&
      await Db.kvGet('last_export_week') != weekStamp();
}
