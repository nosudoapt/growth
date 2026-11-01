import 'dart:convert';

import '../core/db.dart';
import '../seed/feeds.dart';

/// User-managed feed list (bundled six by default; add/remove allowed).
class FeedsRepo {
  const FeedsRepo._();

  static const String _key = 'feeds';

  static Future<List<SeedFeed>> all() async {
    final raw = await Db.kvGet(_key);
    if (raw == null) {
      final seed = [
        for (final f in kSeedFeeds) {'title': f.title, 'url': f.url, 'topic': f.topic},
      ];
      await Db.kvSet(_key, jsonEncode(seed));
      await _ensureReadsSeeded();
      return kSeedFeeds;
    }
    try {
      final l = jsonDecode(raw) as List;
      return [
        for (final e in l.whereType<Map<String, dynamic>>())
          SeedFeed(
              (e['title'] as String?) ?? 'Feed',
              (e['url'] as String?) ?? '',
              (e['topic'] as String?) ?? 'Self-improvement'),
      ];
    } catch (_) {
      return kSeedFeeds;
    }
  }

  static Future<void> add(String title, String url, String topic) async {
    final list = await all();
    if (list.any((f) => f.url == url)) return;
    final next = [
      ...[for (final f in list) {'title': f.title, 'url': f.url, 'topic': f.topic}],
      {'title': title, 'url': url, 'topic': topic},
    ];
    await Db.kvSet(_key, jsonEncode(next));
  }

  static Future<void> remove(String url) async {
    final list = await all();
    final next = [
      for (final f in list)
        if (f.url != url) {'title': f.title, 'url': f.url, 'topic': f.topic},
    ];
    await Db.kvSet(_key, jsonEncode(next));
    final db = await Db.instance();
    await db.delete('reads', where: 'source = ?', whereArgs: [url]);
  }

  static Future<void> _ensureReadsSeeded() async {
    // Nothing extra to seed; reads table fills on first refresh.
    await Db.kvSet('feeds_seeded', '1');
  }
}
