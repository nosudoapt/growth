import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../background/alarms.dart';
import '../core/app_state.dart';
import '../core/db.dart';
import '../core/theme.dart';
import '../logic/profile.dart';
import '../notifications/notifs.dart';
import '../repos/export.dart';
import '../repos/feeds.dart';
import '../repos/llm.dart';
import 'widgets.dart';

/// Settings: provider/base URL/model/key, monthly spend cap, notification
/// and check-in times, dark mode, feeds, goals, export, delete.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _modelCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _capCtrl = TextEditingController();
  LlmProvider _provider = LlmProvider.anthropic;
  bool _hasKey = false;
  bool _dark = true;
  bool _autoAdvance = false;
  double _monthUsd = 0.0;
  int _monthTokens = 0;
  List<SeedFeed> _feeds = [];
  List<String> _goals = [];
  List<String> _hookTimes = [];
  String _checkinTime = '22:35';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final llm = LlmService();
    LlmConfig? config;
    try {
      config = await llm.loadConfig();
    } catch (_) {
      config = null;
    }
    final apiKey = await llm.hasKey();
    final monthUsd = await llm.monthUsageUsd();
    final monthTokens = await llm.monthUsageTokens();
    final dark = await Db.kvGet('light_mode') != '1';
    final auto = await Db.kvGet('auto_advance') == '1';
    final feeds = await FeedsRepo.all();
    final goals = await goalsList();
    final hooks = await NotifSettings.hookTimes();
    final checkin = await Db.kvGet('checkin_time') ?? '22:35';
    if (!mounted) return;
    setState(() {
      _provider = config?.provider ?? LlmProvider.anthropic;
      _baseUrlCtrl.text = config?.baseUrl ?? 'https://api.anthropic.com';
      _modelCtrl.text = config?.model ?? 'claude-sonnet-4-5';
      _capCtrl.text = (config?.monthlyCapUsd ?? 5.0).toStringAsFixed(2);
      _hasKey = apiKey;
      _dark = dark;
      _autoAdvance = auto;
      _monthUsd = monthUsd;
      _monthTokens = monthTokens;
      _feeds = feeds;
      _goals = goals;
      _hookTimes = hooks;
      _checkinTime = checkin;
    });
  }

  Future<void> _saveProvider() async {
    final llm = LlmService();
    final config = LlmConfig(
      provider: _provider,
      baseUrl: _baseUrlCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      apiKeySet: _hasKey,
      monthlyCapUsd: double.tryParse(_capCtrl.text.trim()) ?? 5.0,
    );
    await llm.saveConfig(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved. Key stays on this phone.')));
    _load();
  }

  Future<void> _enterKey() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GCol.surface,
        title: const Text('API key',
            style: TextStyle(fontSize: 20, color: GCol.text)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(fontSize: 16, color: GCol.text),
          decoration: const InputDecoration(
            hintText: 'sk-… (stored in secure storage only)',
            hintStyle: TextStyle(fontSize: 15, color: GCol.muted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: GCol.muted))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save', style: TextStyle(color: GCol.gold))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await LlmService().saveKey(ctrl.text.trim());
      if (mounted) {
        setState(() => _hasKey = true);
      }
    }
    ctrl.dispose();
  }

  Future<void> _removeKey() async {
    await LlmService().deleteKey();
    if (mounted) setState(() => _hasKey = false);
  }

  Future<void> _pickCheckinTime() async {
    final parts = _checkinTime.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.tryParse(parts.isNotEmpty ? parts[0] : '22') ?? 22,
          minute: int.tryParse(parts.length > 1 ? parts[1] : '35') ?? 35),
      builder: (context, child) => Theme(data: buildGrowthTheme(true), child: child ?? const SizedBox.shrink()),
    );
    if (t != null) {
      final hhmm =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      await Db.kvSet('checkin_time', hhmm);
      await GrowthAlarms.scheduleAll();
      if (mounted) setState(() => _checkinTime = hhmm);
    }
  }

  Future<void> _pickHookTimes() async {
    // First hook time picker (second optional) — most reliable single flow.
    final firstParts = (_hookTimes.isNotEmpty ? _hookTimes[0] : '08:30').split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.tryParse(firstParts.isNotEmpty ? firstParts[0] : '8') ?? 8,
          minute: int.tryParse(firstParts.length > 1 ? firstParts[1] : '30') ?? 30),
      builder: (context, child) => Theme(data: buildGrowthTheme(true), child: child ?? const SizedBox.shrink()),
    );
    if (t != null) {
      final hhmm =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      await NotifSettings.setHookTimes([hhmm]);
      if (mounted) setState(() => _hookTimes = [hhmm]);
    }
  }

  Future<void> _editGoals() async {
    final ctrl = TextEditingController(text: _goals.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GCol.surface,
        title: const Text('Goals',
            style: TextStyle(fontSize: 20, color: GCol.text)),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          style: const TextStyle(fontSize: 16, color: GCol.text),
          decoration: const InputDecoration(
            hintText: 'One goal per line',
            hintStyle: TextStyle(fontSize: 16, color: GCol.muted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: GCol.muted))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save', style: TextStyle(color: GCol.gold))),
        ],
      ),
    );
    if (ok == true) {
      final list = ctrl.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await setGoalsList(list.isEmpty ? kSeedGoals : list);
      if (mounted) setState(() => _goals = list.isEmpty ? kSeedGoals : list);
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GCol.bg,
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(
                fontFamily: 'Playfair Display', fontSize: 24, color: GCol.text)),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const _Head('AI (your key, your spend)'),
        SegmentedButton<LlmProvider>(
          segments: const [
            ButtonSegment(
                value: LlmProvider.anthropic, label: Text('Anthropic')),
            ButtonSegment(
                value: LlmProvider.openaiCompatible,
                label: Text('OpenAI-compatible')),
          ],
          selected: {_provider},
          onSelectionChanged: (s) => setState(() => _provider = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baseUrlCtrl,
          style: const TextStyle(fontSize: 16, color: GCol.text),
          decoration: const InputDecoration(
            labelText: 'Base URL (https)',
            labelStyle: TextStyle(fontSize: 16, color: GCol.muted),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelCtrl,
          style: const TextStyle(fontSize: 16, color: GCol.text),
          decoration: const InputDecoration(
            labelText: 'Model',
            labelStyle: TextStyle(fontSize: 16, color: GCol.muted),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(_hasKey ? 'Key saved (secure storage)' : 'No key set',
              style: TextStyle(fontSize: 16, color: _hasKey ? GCol.gold : GCol.muted)),
          const SizedBox(width: 12),
          TextButton(
              onPressed: _enterKey,
              child: Text(_hasKey ? 'Replace' : 'Add key',
                  style: const TextStyle(fontSize: 16, color: GCol.gold))),
          if (_hasKey)
            TextButton(
                onPressed: _removeKey,
                child: const Text('Remove',
                    style: TextStyle(fontSize: 16, color: GCol.muted))),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _capCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 16, color: GCol.text),
          decoration: const InputDecoration(
            labelText: 'Monthly spend cap (USD)',
            labelStyle: TextStyle(fontSize: 16, color: GCol.muted),
          ),
        ),
        const SizedBox(height: 10),
        Text(
            'Estimated spend this month: ${_monthUsd.toStringAsFixed(2)} USD '
            '(≈$_monthTokens tokens). LLM calls stop at the cap.',
            style: const TextStyle(fontSize: 15, color: GCol.muted)),
        const SizedBox(height: 12),
        BigButton(label: 'Save AI settings', onTap: _saveProvider),

        const SizedBox(height: 30),
        const _Head('Notifications'),
        Row(children: [
          const Text('Nightly check-in',
              style: TextStyle(fontSize: 16, color: GCol.text)),
          const Spacer(),
          TextButton(
            onPressed: _pickCheckinTime,
            child: Text(_checkinTime,
                style: const TextStyle(
                    fontSize: 16, color: GCol.gold)),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text('Story hook times (max 2/day, now: ${_hookTimes.join(', ')})',
                style: const TextStyle(fontSize: 16, color: GCol.text)),
          ),
          TextButton(
              onPressed: _pickHookTimes,
              child: const Text('Choose',
                  style: TextStyle(fontSize: 16, color: GCol.gold))),
        ]),
        TextButton(
            onPressed: () async {
              await Permission.notification.request();
            },
            child: const Text('Check notification permission',
                style: TextStyle(fontSize: 16, color: GCol.muted))),

        const SizedBox(height: 30),
        const _Head('Look & feel'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark mode',
              style: TextStyle(fontSize: 16, color: GCol.text)),
          subtitle: const Text('Tonight-appropriate by default',
              style: TextStyle(fontSize: 15, color: GCol.muted)),
          value: _dark,
          onChanged: (v) async {
            await Db.kvSet('light_mode', v ? '0' : '1');
            appTheme.value = v ? ThemeMode.dark : ThemeMode.light;
            if (mounted) setState(() => _dark = v);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-advance the feed',
              style: TextStyle(fontSize: 16, color: GCol.text)),
          subtitle: const Text('12s a thought, 20s a read; long-press pauses',
              style: TextStyle(fontSize: 15, color: GCol.muted)),
          value: _autoAdvance,
          onChanged: (v) async {
            await Db.kvSet('auto_advance', v ? '1' : '0');
            if (mounted) setState(() => _autoAdvance = v);
          },
        ),

        const SizedBox(height: 30),
        const _Head('Feeds'),
        for (final f in _feeds)
          Row(children: [
            Expanded(
              child: Text('${f.title} — ${f.topic}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, color: GCol.text)),
            ),
            IconButton(
              tooltip: 'Remove feed',
              onPressed: () async {
                await FeedsRepo.remove(f.url);
                _load();
              },
              icon: const Icon(Icons.remove_circle_outline,
                  color: GCol.muted, size: 22),
            ),
          ]),
        TextButton(
            onPressed: _addFeed,
            child: const Text('Add a feed',
                style: TextStyle(fontSize: 16, color: GCol.gold))),

        const SizedBox(height: 30),
        const _Head('Goals'),
        Text(_goals.join(' • '),
            style: const TextStyle(fontSize: 16, color: GCol.text)),
        TextButton(
            onPressed: _editGoals,
            child: const Text('Edit goals',
                style: TextStyle(fontSize: 16, color: GCol.gold))),

        const SizedBox(height: 30),
        const _Head('Your data'),
        TextButton(
            onPressed: () async {
              await Exports.shareAllData();
            },
            child: const Text('Export everything (JSON, no key)',
                style: TextStyle(fontSize: 16, color: GCol.text))),
        TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: GCol.surface,
                  title: const Text('Delete everything?',
                      style: TextStyle(fontSize: 20, color: GCol.text)),
                  content: const Text(
                      'All check-ins, reads, notes, goals and dashboards '
                      'are wiped from this phone. This cannot be undone.',
                      style: TextStyle(fontSize: 16, color: GCol.muted)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: GCol.muted))),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete',
                            style: TextStyle(color: GCol.ember))),
                  ],
                ),
              );
              if (ok == true) {
                await Exports.deleteAll();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All data deleted.')));
                }
                _load();
              }
            },
            child: const Text('Delete all data',
                style: TextStyle(fontSize: 16, color: GCol.ember))),
      ]),
    );
  }

  Future<void> _addFeed() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GCol.surface,
        title: const Text('Add feed',
            style: TextStyle(fontSize: 20, color: GCol.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: titleCtrl,
            style: const TextStyle(fontSize: 16, color: GCol.text),
            decoration: const InputDecoration(labelText: 'Title',
                labelStyle: TextStyle(fontSize: 16, color: GCol.muted)),
          ),
          TextField(
            controller: urlCtrl,
            style: const TextStyle(fontSize: 16, color: GCol.text),
            decoration: const InputDecoration(labelText: 'HTTPS RSS URL',
                labelStyle: TextStyle(fontSize: 16, color: GCol.muted)),
          ),
          TextField(
            controller: topicCtrl,
            style: const TextStyle(fontSize: 16, color: GCol.text),
            decoration: const InputDecoration(labelText: 'Topic',
                labelStyle: TextStyle(fontSize: 16, color: GCol.muted)),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: GCol.muted))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add', style: TextStyle(color: GCol.gold))),
        ],
      ),
    );
    if (ok == true) {
      final url = urlCtrl.text.trim();
      if (url.startsWith('https://')) {
        await FeedsRepo.add(titleCtrl.text.trim(), url,
            topicCtrl.text.trim().isEmpty ? 'Self-improvement' : topicCtrl.text.trim());
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Only HTTPS feeds are accepted.')));
      }
    }
    titleCtrl.dispose();
    urlCtrl.dispose();
    topicCtrl.dispose();
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'Playfair Display', fontSize: 20, color: GCol.gold)),
    );
  }
}

// Small local helpers so goals stay in one place across screens.
Future<List<String>> goalsList() async {
  final raw = await Db.kvGet('goals');
  if (raw == null || raw.isEmpty) return kSeedGoals;
  try {
    final l = jsonDecode(raw) as List;
    return l.whereType<String>().toList();
  } catch (_) {
    return kSeedGoals;
  }
}

Future<void> setGoalsList(List<String> g) =>
    Db.kvSet('goals', jsonEncode(g));
