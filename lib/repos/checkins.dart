import 'dart:convert';

import '../core/db.dart';
import '../logic/rotation.dart';
import '../seed/questions.dart';
import 'package:sqflite/sqflite.dart';

/// One night's submitted check-in record.
class CheckInRecord {
  const CheckInRecord({
    required this.id,
    required this.date,
    required this.question,
    required this.answer,
    required this.mood,
    required this.focus,
    required this.timeWellSpent,
    required this.isFollowup,
    required this.pendingSync,
  });

  final int id;
  final String date;
  final String question;
  final String answer;
  final int mood;
  final int focus;
  final int timeWellSpent;
  final bool isFollowup;
  final bool pendingSync;
}

/// The nightly check-in: rotating questions (no repeats in 14 days), up to 3
/// sliders, one optional LLM follow-up with a hard cap of 4 questions/night.
class CheckinRepo {
  const CheckinRepo._();

  static const int maxQuestionsPerNight = 4;

  /// Next question index for a date, given the question history.
  static Future<int> nextQuestionIndex() async {
    final db = await Db.instance();
    final rows = await db.query('question_history',
        orderBy: 'date DESC', limit: 31);
    final today = DateTime.now();
    final recent = Rotation.recentSince(
      [
        for (final r in rows)
          (r['date'] as String, r['question_index'] as int),
      ],
      14,
      today,
    );
    return Rotation.nextIndex(kCheckinQuestions.length, recent);
  }

  static Future<String> nextQuestion() async {
    final idx = await nextQuestionIndex();
    return kCheckinQuestions[idx];
  }

  static Future<void> rememberQuestionIndex(
      String date, int index) async {
    final db = await Db.instance();
    await db.insert('question_history', {'date': date, 'question_index': index},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Count of questions answered tonight (respects the hard cap of 4).
  static Future<int> answeredTonight(String date) async {
    final db = await Db.instance();
    final c = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM checkins WHERE date = ?', [date]);
    return (c.first['c'] as num).toInt();
  }

  /// Save an answer + the three sliders. `pendingSync` marks it for the LLM
  /// dashboard pass that runs later when online. Purely local, idempotent by
  /// (date, question) — resubmission replaces.
  static Future<int> save({
    String? date,
    required String question,
    required String answer,
    required int mood,
    required int focus,
    required int timeWellSpent,
    bool isFollowup = false,
  }) async {
    final db = await Db.instance();
    final d = date ?? Db.today();
    await db.delete('checkins',
        where: 'date = ? AND question = ?', whereArgs: [d, question]);
    final id = await db.insert('checkins', {
      'date': d,
      'question': question,
      'answer': answer,
      'mood': mood,
      'focus': focus,
      'time_well_spent': timeWellSpent,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'is_followup': isFollowup ? 1 : 0,
      'pending_sync': 0,
    });
    return id;
  }

  /// Last N nights of full records (plain JSON strings for the LLM prompt).
  static Future<List<Map<String, dynamic>>> lastNights(int n) async {
    final db = await Db.instance();
    final rows = await db.query('checkins',
        orderBy: 'ts DESC', limit: 60);
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r['date'] as String, () => []).add({
        'question': r['question'],
        'answer': r['answer'],
        'mood': r['mood'],
        'focus': r['focus'],
        'time_well_spent': r['time_well_spent'],
        'is_followup': r['is_followup'],
        'date': r['date'],
      });
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final d in dates.take(n)) ...byDate[d]!,
    ];
  }

  /// Averages for the self-improvement trends.
  static Future<Map<String, Map<String, double>>> averagesByDate(
      int days) async {
    final db = await Db.instance();
    final rows = await db.query('checkins',
        where: 'is_followup = 0',
        columns: [
          'date',
          'AVG(mood) AS m',
          'AVG(focus) AS f',
          'AVG(time_well_spent) AS t',
        ],
        groupBy: 'date');
    final out = <String, Map<String, double>>{};
    for (final r in rows) {
      out[r['date'] as String] = {
        'mood': (r['m'] as num? ?? 3).toDouble(),
        'focus': (r['f'] as num? ?? 3).toDouble(),
        'time': (r['t'] as num? ?? 3).toDouble(),
      };
    }
    return out;
  }

  /// Whether tonight was completed (base question + optional follow-ups).
  static Future<bool> completedTonight([String? date]) async {
    final n = await answeredTonight(date ?? Db.today());
    return n > 0;
  }

  static Future<void> setNightState(String date, String state) =>
      Db.kvSet('checkin_state_$date', state);
}

class CheckinJson {
  const CheckinJson._();

  static String encode(List<Map<String, dynamic>> all) =>
      jsonEncode(all);
}
