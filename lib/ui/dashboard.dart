import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/dashboard.dart';
import '../repos/dashboard.dart';
import '../repos/llm.dart';
import '../repos/profile.dart';
import 'charts.dart';

/// LLM dashboard, six tabs, each stamped "Last updated".
class DashboardPage extends rp.ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  rp.ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends rp.ConsumerState<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);
  DashboardData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await DashboardRepo.current();
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  Future<void> _refreshNow() async {
    setState(() => _loading = true);
    try {
      final llm = LlmService();
      final config = await llm.loadConfig();
      if (config.apiKeySet) {
        final profile = await ProfileRepo.current();
        await DashboardRepo.rebuild(
            llm: llm,
            config: config,
            profileText: profile,
            weekly: DateTime.now().weekday == DateTime.sunday);
      }
    } catch (_) {
      // Calm: the last good dashboard stays.
    }
    await _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stamp = _data == null ? 'Never updated' : _stamp(_data!.updatedAt);
    return Scaffold(
      backgroundColor: GCol.bg,
      appBar: AppBar(
        title: Text('Dashboard',
            style: const TextStyle(
                fontFamily: 'Playfair Display',
                fontSize: 24,
                color: GCol.text)),
        actions: [
          IconButton(
            tooltip: 'Refresh now',
            onPressed: _loading ? null : _refreshNow,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: GCol.text,
          unselectedLabelColor: GCol.muted,
          indicatorColor: GCol.gold,
          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15),
          tabs: const [
            Tab(text: 'Self-improvement'),
            Tab(text: 'Reading'),
            Tab(text: 'Favorites'),
            Tab(text: 'Good habits'),
            Tab(text: 'Bad habits'),
            Tab(text: 'Progress'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: GCol.gold))
          : TabBarView(
              controller: _tabs,
              children: [
                _TabScaffold(stamp: stamp, child: _selfImprovement()),
                _TabScaffold(stamp: stamp, child: _reading()),
                _TabScaffold(stamp: stamp, child: _favorites()),
                _TabScaffold(stamp: stamp, child: _goodHabits()),
                _TabScaffold(stamp: stamp, child: _badHabits()),
                _TabScaffold(stamp: stamp, child: _progress()),
              ],
            ),
    );
  }

  String _stamp(DateTime t) => 'Last updated ${DateFormat('EEE, HH:mm').format(t)}';

  List<String> _lastDates(int n) {
    final now = DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        now.subtract(Duration(days: i)).toIso8601String().substring(0, 10)
    ];
  }

  // Tab 1: trends + weekly suggestion.
  Widget _selfImprovement() {
    final d7 = _lastDates(7);
    final d30 = _lastDates(30);
    final data = _data;
    Widget chart(String key, double maxValue, List<String> dates) {
      final list = data == null
          ? List<double>.filled(dates.length, 0)
          : _series(data, key, dates);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key,
              style: const TextStyle(fontSize: 16, color: GCol.muted)),
          TrendLineChart(
              values: list,
              color: GCol.gold,
              maxValue: maxValue,
              label: ''),
          const SizedBox(height: 10),
        ],
      );
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      ..._trendSection(d7, 'Last 7 days'),
      ..._trendSection(d30, 'Last 30 days'),
      const SizedBox(height: 12),
      const Divider(color: GCol.surface, height: 32),
      const Text('One suggestion for your week',
          style: TextStyle(
              fontFamily: 'Playfair Display',
              fontSize: 22,
              color: GCol.text)),
      const SizedBox(height: 8),
      Text(
        _data != null && _data!.weeklySuggestion.isNotEmpty
            ? _data!.weeklySuggestion
            : 'You will see a weekly suggestion after your first check-in.',
        style: const TextStyle(fontSize: 17, height: 1.5, color: GCol.text),
      ),
    ]);
  }

  List<Widget> _trendSection(List<String> dates, String title) {
    final data = _data;
    return [
      Text(title,
          style: const TextStyle(
              fontFamily: 'Playfair Display', fontSize: 20, color: GCol.text)),
      const SizedBox(height: 8),
      if (data != null) ...[
        chart('mood_trend', 5, dates),
        chart('focus_trend', 5, dates),
        chart('time_well_spent_trend', 5, dates),
      ],
    ];
  }

  List<double> _series(DashboardData data, String key, List<String> dates) {
    final list = (data.raw[key] ?? const <dynamic>[]) as List;
    final perDate = <String, double>{};
    for (final item in list) {
      if (item is Map<String, dynamic> &&
          item['date'] is String &&
          item['value'] is num) {
        perDate[item['date'] as String] = (item['value'] as num).toDouble();
      }
    }
    return [for (final d in dates) perDate[d] ?? 0.0];
  }

  // Tab 2: reading.
  Widget _reading() {
    final data = _data;
    final minutes = data != null
        ? ((data.reading['minutes_by_day'] ?? const <dynamic>[]) as List)
        : const <dynamic>[];
    final values = [
      for (final item in minutes)
        if (item is Map<String, dynamic> && item['minutes'] is num)
          (item['minutes'] as num).toDouble()
    ];
    final byTopic = data != null
        ? ((data.reading['finished_by_topic'] ?? const <String, dynamic>{})
            as Map<String, dynamic>)
        : const <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Minutes per day',
          style: TextStyle(fontFamily: 'Playfair Display', fontSize: 20, color: GCol.text)),
      const SizedBox(height: 10),
      MinuteBarChart(values: values.isEmpty ? List.filled(7, 0) : values),
      const SizedBox(height: 16),
      Row(children: [
        _MetricCard(label: 'Current streak', value: data?.readingStreak ?? 0),
        const SizedBox(width: 12),
        _MetricCard(label: 'Longest streak', value: data?.readingLongest ?? 0),
      ]),
      const SizedBox(height: 18),
      const Text('Finished by topic',
          style: TextStyle(fontFamily: 'Playfair Display', fontSize: 20, color: GCol.text)),
      const SizedBox(height: 8),
      if (byTopic.isEmpty)
        const Text('No finishes yet — that changes quietly.',
            style: TextStyle(fontSize: 16, color: GCol.muted))
      else
        ...[for (final e in byTopic.entries) Row(
              children: [
                const Icon(Icons.circle, color: GCol.gold, size: 8),
                const SizedBox(width: 10),
                Text('${e.key} — ${e.value}',
                    style:
                        const TextStyle(fontSize: 16, color: GCol.text)),
              ],
            )],
    ]);
  }

  // Tab 3: favorites.
  Widget _favorites() {
    final items = _data?.favorites ?? const <Map<String, dynamic>>[];
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (items.isEmpty)
        const Text('Like a few cards and your favorites will appear here.',
            style: TextStyle(fontSize: 16, color: GCol.muted))
      else
        for (final f in items) Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f['name']} • ${f['type']} (${f['likes']})',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: GCol.gold)),
            const SizedBox(height: 4),
            Text(f['why'] as String? ?? '',
                style: const TextStyle(fontSize: 16, color: GCol.text)),
          ]),
        ),
    ]);
  }

  // Tab 4: good habits.
  Widget _goodHabits() {
    final items = _data?.goodHabits ?? const <Map<String, dynamic>>[];
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (items.isEmpty)
        const Text(
            'Good habits appear after a few nights of check-ins.',
            style: TextStyle(fontSize: 16, color: GCol.muted))
      else
        for (final h in items) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${h['name']} — ${((h['consistency_pct'] as num?) ?? 0).toInt()}%',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: GCol.gold)),
            const SizedBox(height: 4),
            Text(h['note'] as String? ?? '',
                style: const TextStyle(fontSize: 16, color: GCol.text)),
          ]),
        ),
    ]);
  }

  // Tab 5: bad habits — patterns only, never diagnosis, one alternative each.
  Widget _badHabits() {
    final items = _data?.badHabits ?? const <Map<String, dynamic>>[];
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Patterns are not verdicts. Each one has a gentle alternative.',
          style: TextStyle(fontSize: 16, color: GCol.muted)),
      const SizedBox(height: 14),
      if (items.isEmpty)
        const Text('Nothing flagged yet.',
            style: TextStyle(fontSize: 16, color: GCol.muted))
      else
        for (final h in items) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h['pattern'] as String? ?? '',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: GCol.text)),
            const SizedBox(height: 4),
            Text('Gentle alternative: ${h['gentle_alternative'] ?? ''}',
                style: const TextStyle(
                    fontSize: 16, height: 1.5, color: GCol.gold)),
          ]),
        ),
    ]);
  }

  // Tab 6: progress + win.
  Widget _progress() {
    final items = _data?.progress ?? const <Map<String, dynamic>>[];
    final win = _data?.winOfTheWeek ?? '';
    String arrow(num a, num b) {
      if (a > b) return '↑';
      if (a < b) return '↓';
      return '→';
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GCol.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GCol.gold.withValues(alpha: .4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Win of the week',
              style: TextStyle(
                  fontFamily: 'Playfair Display',
                  fontSize: 20,
                  color: GCol.gold)),
          const SizedBox(height: 6),
          Text(win.isEmpty ? 'Your first week will have its own wins.' : win,
              style: const TextStyle(fontSize: 17, height: 1.5, color: GCol.text)),
        ]),
      ),
      const SizedBox(height: 20),
      if (items.isEmpty)
        const Text('Week-over-week changes appear after two check-in weekends.',
            style: TextStyle(fontSize: 16, color: GCol.muted))
      else
        for (final p in items) Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 34,
              child: Text(
                  arrow((p['this_week'] as num?) ?? 0, (p['last_week'] as num?) ?? 0),
                  style: const TextStyle(fontSize: 18, color: GCol.gold)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['metric']} — ${((p['this_week'] as num?) ?? 0)} vs ${((p['last_week'] as num?) ?? 0)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: GCol.text)),
                const SizedBox(height: 2),
                Text(p['note'] as String? ?? '',
                    style: const TextStyle(fontSize: 16, color: GCol.muted)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.stamp, required this.child});

  final String stamp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(child: GrainOverlay()),
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(stamp,
              style: const TextStyle(fontSize: 15, color: GCol.muted)),
        ),
        Expanded(child: child),
      ]),
    ]);
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GCol.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value day${value == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontFamily: 'Playfair Display',
                  fontSize: 26,
                  color: GCol.gold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 15, color: GCol.muted)),
        ]),
      ),
    );
  }
}
