import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../core/db.dart';
import 'package:sqflite/sqflite.dart';

/// One cached read item.
class ReadItem {
  const ReadItem({
    required this.id,
    required this.guid,
    required this.source,
    required this.topic,
    required this.title,
    required this.summary,
    required this.opened,
    required this.liked,
    required this.skipped,
    required this.saved,
    required this.minutes,
    required this.note,
  });

  final int id;
  final String guid;
  final String source;
  final String topic;
  final String title;
  final String summary;
  final bool liked;
  final bool skipped;
  final bool saved;
  final bool opened;
  final double minutes;
  final String note;

  int estimatedMinutes() {
    final words = ('$title $summary').split(RegExp(r'\s+')).length;
    final mins = words / 200;
    if (mins < 1) return 1;
    return mins.round();
  }
}

/// Fetches the user's feeds (HTTPS, timeout, backoff) and caches items.
/// Idempotent: re-running produces the same stored rows (guid upsert).
class RssRepo {
  RssRepo({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Fetch one feed and store new items. Returns the number stored.
  Future<int> fetchAndCache(String url, String topic) async {
    final raw = await _fetch(url);
    return store(url, topic, raw);
  }

  Future<String> _fetch(String url, {int attempt = 0}) async {
    if (!url.startsWith('https://')) return '';
    try {
      final resp = await _client
          .get(Uri.parse(url), headers: {'user-agent': 'Growth/1.0 (RSS reader; offline-first)'})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes);
      if ((resp.statusCode == 429 || resp.statusCode >= 500) && attempt < 1) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      return '';
    } catch (_) {
      if (attempt < 1) {
        await Future<void>.delayed(const Duration(seconds: 3));
        try {
          final resp = await _client
              .get(Uri.parse(url), headers: {'user-agent': 'Growth/1.0 (RSS reader; offline-first)'})
              .timeout(const Duration(seconds: 20));
          if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes);
        } catch (_) {}
      }
      return '';
    }
  }

  /// Store parsed items; upsert on guid so runs are idempotent.
  Future<int> store(String url, String topic, String raw) async {
    if (raw.isEmpty) return 0;
    final items = parseFeed(raw);
    var stored = 0;
    final db = await Db.instance();
    for (final it in items) {
      final guid = '$url#${it['guid'] ?? it['title']}';
      try {
        final r = await db.insert('reads', {
          'guid': guid,
          'source': it['source'] ?? url,
          'topic': topic,
          'title': it['title'] ?? '',
          'summary': stripHtml(it['summary'] ?? ''),
          'published': it['published'] ?? '',
          'cached_at': Db.today(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (r > 0) stored++;
      } catch (_) {
        // Unique violation already handled by IGNORE; other errors tolerated.
      }
    }
    return stored;
  }

  /// Minimal RSS / Atom / RDF parser. Defensive: bad XML → empty list.
  static List<Map<String, String?>> parseFeed(String raw) {
    try {
      final doc = XmlDocument.parse(raw);
      final rssItems = doc.findAllElements('item');
      final atomEntries = doc.findAllElements('entry');
      final nodes = rssItems.isNotEmpty
          ? rssItems
          : (atomEntries.isNotEmpty ? atomEntries : doc.findAllElements('rdf:item'));
      final out = <Map<String, String?>>[];
      for (final n in nodes) {
        String? text(String tag) => n.descendantElements
                .where((e) => e.name.local == tag)
                .map((e) => e.innerText)
                .firstOrNull;
        out.add({
          'title': text('title')?.trim(),
          'summary': (text('description') ?? text('content'))?.trim(),
          'published': text('pubDate') ?? text('published') ?? text('dc:date'),
          'source': text('source'),
          'guid': text('guid'),
        });
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String stripHtml(String s) {
    var t = s
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8217;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 1200) t = t.substring(0, 1200);
    return t;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
