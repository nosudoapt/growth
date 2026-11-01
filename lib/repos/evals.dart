import 'dart:convert';

import '../core/db.dart';
import '../logic/eval_logic.dart';
import '../seed/eval_items.dart';
import 'llm.dart';
import 'prompts.dart';

/// Eval set: 50 bundled items rated by the user (1–5). "Run eval" sends them
/// through the current ranking prompt and stores agreement by prompt version.
class EvalRepo {
  const EvalRepo._();

  static Future<void> ensureSeeded() async {
    final db = await Db.instance();
    final c = await db.query('eval_items', columns: ['id'], limit: 1);
    if (c.isNotEmpty) return;
    for (var i = 0; i < kEvalItems.length; i++) {
      await db.insert('eval_items', {
        'id': i + 1,
        'title': kEvalItems[i],
        'user_rating': null,
        'model_rating': null,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> items() async {
    final db = await Db.instance();
    return db.query('eval_items', orderBy: 'id');
  }

  static Future<int> ratedCount() async {
    final db = await Db.instance();
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM eval_items WHERE user_rating IS NOT NULL');
    return (r.first['c'] as num).toInt();
  }

  static Future<void> rate(int id, int userRating) async {
    final db = await Db.instance();
    await db.update('eval_items', {'user_rating': userRating},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Runs the ranking prompt on all rated items. Returns (agreementPct, mae).
  static Future<(double, double)> run({
    required LlmService llm,
    required LlmConfig config,
  }) async {
    final db = await Db.instance();
    final rows = await db.query('eval_items',
        where: 'user_rating IS NOT NULL', orderBy: 'id');
    if (rows.isEmpty) return (0.0, 0.0);

    final itemsJson = [
      for (final r in rows) {'id': r['id'], 'title': r['title']},
    ];
    final prompt = Prompts.ranking(jsonEncode(itemsJson));

    final pairs = await llm.complete<List<(int, int)>>(
      config: config,
      system:
          'You rate reading items 1-5 for practical value. Reply with ONLY valid JSON.',
      prompt: prompt,
      maxOutputTokens: 1200,
      parse: (t) {
        final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
        var s = fence?.group(1)?.trim() ?? t.trim();
        final start = s.indexOf('{');
        final end = s.lastIndexOf('}');
        s = s.substring(start, end + 1);
        final obj = jsonDecode(s) as Map<String, dynamic>;
        final list = (obj['ratings'] as List?) ?? const [];
        final out = <(int, int)>[];
        final byId = <int, int>{
          for (final r in rows) (r['id'] as num).toInt(): (r['user_rating'] as num).toInt()
        };
        final modelById = <int, int>{};
        for (final entry in list) {
          if (entry is Map<String, dynamic> &&
              entry['id'] is num &&
              entry['score'] is num) {
            final id = (entry['id'] as num).toInt();
            final user = byId[id];
            if (user == null) continue;
            out.add((user, (entry['score'] as num).toInt()));
            // Keep each per-item model rating for the screen.
            modelById[id] = (entry['score'] as num).toInt();
          } else {
            throw const FormatException('bad rating entry');
          }
        }
        if (out.length != byId.length || modelById.isEmpty) {
          throw const FormatException('missing rating entries');
        }
        return out;
      },
    );

    final agree = EvalScoring.agreementPct(pairs);
    final mae = EvalScoring.mae(pairs);
    await db.insert('eval_runs', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'prompt_version': Prompts.rankingVersion,
      'agreement_pct': agree,
      'mae': mae,
    });
    return (agree, mae);
  }

  static Future<List<Map<String, dynamic>>> runs() async {
    final db = await Db.instance();
    return db.query('eval_runs', orderBy: 'ts DESC', limit: 20);
  }
}
