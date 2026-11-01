import 'dart:convert';

import '../core/db.dart';
import 'rss.dart';

/// Local-first store for reads, likes/skips/saves/notes, and daily reading
/// time. Every interaction is appended to `interactions` so dashboards and
/// exports can replay what happened.
class LibraryRepo {
  const LibraryRepo._();

  /// Items not yet skipped, oldest-cached last → shown first.
  static Future<List<ReadItem>> fresh() async {
    final db = await Db.instance();
    final rows = await db.query('reads',
        where: 'skipped = 0',
        orderBy: 'id DESC',
        limit: 120);
    return rows.map(_fromRow).toList();
  }

  static Future<List<ReadItem>> savedItems() async {
    final db = await Db.instance();
    final rows = await db
        .query('reads', where: 'saved = 1', orderBy: 'id DESC');
    return rows.map(_fromRow).toList();
  }

  static Future<ReadItem?> byId(int id) async {
    final db = await Db.instance();
    final rows = await db
        .query('reads', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  static ReadItem _fromRow(Map<String, Object?> r) => ReadItem(
        id: r['id'] as int,
        guid: r['guid'] as String,
        source: r['source'] as String,
        topic: r['topic'] as String,
        title: r['title'] as String,
        summary: r['summary'] as String,
        opened: (r['opened'] as int? ?? 0) == 1,
        liked: (r['liked'] as int? ?? 0) == 1,
        skipped: (r['skipped'] as int? ?? 0) == 1,
        saved: (r['saved'] as int? ?? 0) == 1,
        minutes: (r['minutes_spent'] as num? ?? 0).toDouble(),
        note: r['note'] as String? ?? '',
      );

  static Future<void> markOpened(int id) async {
    await _setFlag(id, 'opened', 1);
  }

  static Future<void> markSkipped(int id) async {
    final item = await byId(id);
    await _setFlag(id, 'skipped', 1);
    if (item != null) {
      await recordInteraction('skip', 'read', item.guid);
      await _bumpTopicWeight(item.topic, -1);
    }
  }

  static Future<void> markLiked(int id) async {
    final item = await byId(id);
    if (item == null) return;
    if (item.liked) return;
    await _setFlag(id, 'liked', 1);
    await recordInteraction('like', 'read', item.guid,
        note: item.topic);
    await _bumpTopicWeight(item.topic, 1);
  }

  static Future<void> unmarkLiked(int id) async {
    await _setFlag(id, 'liked', 0);
  }

  static Future<void> toggleSaved(int id) async {
    final item = await byId(id);
    if (item == null) return;
    await _setFlag(id, 'saved', item.saved ? 0 : 1);
    await recordInteraction(
        item.saved ? 'unsave' : 'save', 'read', item.guid);
  }

  static Future<void> setNote(int id, String note) async {
    final db = await Db.instance();
    await db.update('reads', {'note': note}, where: 'id = ?', whereArgs: [id]);
    final item = await byId(id);
    if (item != null) {
      await recordInteraction('note', 'read', item.guid, note: note);
    }
  }

  static Future<void> _setFlag(int id, String flag, int v) async {
    final db = await Db.instance();
    await db.update('reads', {flag: v}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> recordInteraction(
    String kind,
    String itemType,
    String itemKey, {
    String note = '',
  }) async {
    final db = await Db.instance();
    await db.insert('interactions', {
      'kind': kind,
      'item_type': itemType,
      'item_key': itemKey,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'note': note,
    });
  }

  static Future<void> _bumpTopicWeight(String topic, int delta) async {
    final raw = await Db.kvGet('topic_weights');
    final map = raw == null
        ? <String, int>{}
        : (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
    map[topic] = (map[topic] ?? 0) + delta;
    await Db.kvSet('topic_weights', jsonEncode(map));
  }

  /// "More like this": raises the item's topic weight so the next card comes
  /// from the same topic (a local rerank; runs offline).
  static Future<void> moreLikeThis(int id) async {
    final item = await byId(id);
    if (item == null) return;
    await recordInteraction('more_like_this', 'read', item.guid,
        note: item.topic);
    await _bumpTopicWeight(item.topic, 3);
    await Db.kvSet('more_like_topic', item.topic);
  }

  static Future<String?> moreLikeTopic() => Db.kvGet('more_like_topic');

  /// ---- Reading time -----------------------------------------------------

  /// Store actual time spent per day; `minutes` is delta since last save.
  static Future<void> addReadingTime(int itemId, double minutes,
      {String? date}) async {
    if (minutes <= 0) return;
    final db = await Db.instance();
    final d = date ?? Db.today();
    final rows = await db.query('reading_time',
        where: 'date = ? AND item_id = ?', whereArgs: [d, itemId], limit: 1);
    if (rows.isEmpty) {
      await db.insert('reading_time',
          {'date': d, 'item_id': itemId, 'minutes': minutes});
    } else {
      final cur = (rows.first['minutes'] as num).toDouble();
      await db.update(
        'reading_time',
        {'minutes': cur + minutes},
        where: 'date = ? AND item_id = ?',
        whereArgs: [d, itemId],
      );
    }
    await db.execute(
        'UPDATE reads SET minutes_spent = minutes_spent + ? WHERE id = ?',
        [minutes, itemId]);
  }

  static Future<Map<String, double>> minutesByDay({int days = 30}) async {
    final db = await Db.instance();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final iso = cutoff.toIso8601String().substring(0, 10);
    final rowsT = await db.query('reading_time',
        where: 'date >= ?', whereArgs: [iso],
        columns: ['date', 'SUM(minutes) AS m'], groupBy: 'date');
    final out = <String, double>{};
    for (final r in rowsT) {
      out[r['date'] as String] = (r['m'] as num? ?? 0).toDouble();
    }
    return out;
  }

  /// Reading minutes today (for the streak nudge condition).
  static Future<double> todayMinutes() async {
    final m = await minutesByDay(days: 1);
    return m[Db.today()] ?? 0.0;
  }

  static Future<int> likeCount(String itemKey) async {
    final db = await Db.instance();
    final c = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM interactions WHERE kind = 'like' AND item_key = ?",
        [itemKey]);
    return (c.first['c'] as num).toInt();
  }
}
