import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. Everything the app knows lives here — there is no
/// backend. Idempotency keys (kv date stamps) let background jobs run twice.
class Db {
  Db._();
  static Database? _db;

  static Future<Database> instance() async {
    final db = _db;
    if (db != null && db.isOpen) return db;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'growth.db'),
      version: 1,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await d.execute('''
          CREATE TABLE reads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            guid TEXT NOT NULL UNIQUE,
            source TEXT NOT NULL,
            topic TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            published TEXT NOT NULL,
            cached_at TEXT NOT NULL,
            liked INTEGER NOT NULL DEFAULT 0,
            skipped INTEGER NOT NULL DEFAULT 0,
            saved INTEGER NOT NULL DEFAULT 0,
            opened INTEGER NOT NULL DEFAULT 0,
            minutes_spent REAL NOT NULL DEFAULT 0,
            note TEXT NOT NULL DEFAULT ''
          )''');
        await d.execute('''
          CREATE TABLE interactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            item_type TEXT NOT NULL,
            item_key TEXT NOT NULL,
            ts INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT ''
          )''');
        await d.execute('''
          CREATE TABLE checkins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            mood INTEGER NOT NULL DEFAULT 3,
            focus INTEGER NOT NULL DEFAULT 3,
            time_well_spent INTEGER NOT NULL DEFAULT 3,
            ts INTEGER NOT NULL,
            is_followup INTEGER NOT NULL DEFAULT 0,
            pending_sync INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE question_history (
            date TEXT PRIMARY KEY,
            question_index INTEGER NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE thought_days (
            date TEXT PRIMARY KEY,
            thought_index INTEGER NOT NULL,
            content TEXT NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE reading_time (
            date TEXT NOT NULL,
            item_id INTEGER NOT NULL,
            minutes REAL NOT NULL,
            PRIMARY KEY (date, item_id)
          )''');
        await d.execute('''
          CREATE TABLE dashboards (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_good INTEGER NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE eval_items (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            user_rating INTEGER,
            model_rating INTEGER
          )''');
        await d.execute('''
          CREATE TABLE eval_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            prompt_version TEXT NOT NULL,
            agreement_pct REAL NOT NULL,
            mae REAL NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE token_usage (
            month TEXT PRIMARY KEY,
            estimated_tokens INTEGER NOT NULL,
            estimated_usd REAL NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE profile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            body TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
        await d.execute(
            'CREATE INDEX idx_reads_guid ON reads(guid)');
      },
      onUpgrade: (d, oldV, newV) async {},
    );
    return _db!;
  }

  // Convenience kv helpers.

  static Future<String?> kvGet(String key) async {
    final db = await instance();
    final rows = await db
        .query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<void> kvSet(String key, String value) async {
    final db = await instance();
    await db.insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> kvDelete(String key) async {
    final db = await instance();
    await db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }

  static String today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Full wipe for "delete all data".
  static Future<void> wipe() async {
    final db = await instance();
    for (final t in [
      'kv', 'reads', 'interactions', 'checkins', 'question_history',
      'thought_days', 'reading_time', 'dashboards', 'eval_items',
      'eval_runs', 'token_usage', 'profile',
    ]) {
      await db.delete(t);
    }
  }
}
