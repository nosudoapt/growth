import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;

import 'package:intl/intl.dart';

import '../background/alarms.dart' show queueFollowUpRebuild;
import '../core/db.dart';
import '../core/theme.dart';
import '../repos/checkins.dart';
import '../repos/dashboard.dart';
import '../repos/llm.dart';
import '../repos/profile.dart';
import '../repos/prompts.dart';
import '../seed/questions.dart';
import 'widgets.dart';

/// The nightly ritual at 22:35 — deliberately the opposite of the feed:
/// slow, quiet, dark, one question per screen, large text, skip allowed.
class CheckinPage extends rp.ConsumerStatefulWidget {
  const CheckinPage({super.key});

  @override
  rp.ConsumerState<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends rp.ConsumerState<CheckinPage> {
  final _answer = TextEditingController();
  int _questionIndex = 0;
  String _question = '';
  int _mood = 3;
  int _focus = 3;
  int _timeWell = 3;
  bool _loading = true;
  bool _saving = false;
  String? _followup;
  String? _doneMessage;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_doneMessage != null) return _NightSide(child: _wrapDone(_doneMessage!));
    if (_loading) {
      return const _NightSide(
          child: Center(child: CircularProgressIndicator(color: GCol.gold)));
    }
    return _NightSide(
      child: _questionScreen(isFollowup: _followup != null),
    );
  }

  Future<void> _init() async {
    final idx = await CheckinRepo.nextQuestionIndex();
    final q = kCheckinQuestions[idx];
    if (!mounted) return;
    setState(() {
      _questionIndex = idx;
      _question = q;
      _loading = false;
    });
  }

  Widget _questionScreen({required bool isFollowup}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
      child: ListView(
        children: [
          Text(
            DateFormat('EEE d MMMM').format(DateTime.now()),
            style: const TextStyle(fontSize: 16, color: GCol.muted),
          ),
          const SizedBox(height: 24),
          Text(
            _followup ?? _question,
            style: const TextStyle(
              fontFamily: 'Playfair Display',
              fontSize: 30,
              height: 1.25,
              color: GCol.text,
              fontVariations: [FontVariation('wght', 500)],
            ),
          ),
          const SizedBox(height: 28),
          if (!isFollowup) ..._sliderSet(),
          const SizedBox(height: 16),
          TextField(
            controller: _answer,
            enabled: !_saving,
            maxLines: 5,
            maxLength: 600,
            style: const TextStyle(
                fontSize: 19, height: 1.5, color: GCol.text),
            decoration: const InputDecoration(
              hintText: 'Write freely. Only you will see this.',
              hintStyle: TextStyle(fontSize: 19, color: GCol.muted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: GCol.surface),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: GCol.gold),
              ),
            ),
          ),
          const SizedBox(height: 18),
          BigButton(
            label: isFollowup ? 'Answer' : 'Save tonight',
            onTap: _saving ? null : _submit,
          ),
          TextButton(
            onPressed: _saving ? null : _skipTonight,
            child: Text(
              isFollowup ? 'No follow-up needed' : 'Skip tonight',
              style: const TextStyle(fontSize: 16, color: GCol.muted),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sliderSet() {
    Widget slider({
      required String label,
      required int value,
      required ValueChanged<double> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: GCol.muted)),
          Slider(
            min: 1,
            max: 5,
            divisions: 4,
            value: value.toDouble(),
            label: '$value',
            onChangeStart: (_) => HapticFeedback.selectionClick(),
            onChanged: (v) {
              onChanged(v);
              HapticFeedback.lightImpact();
            },
          ),
        ],
      );
    }

    return [
      slider(
          label: 'Mood tonight',
          value: _mood,
          onChanged: (v) => setState(() => _mood = v.round())),
      slider(
          label: 'Focus today',
          value: _focus,
          onChanged: (v) => setState(() => _focus = v.round())),
      slider(
          label: 'Time felt well spent',
          value: _timeWell,
          onChanged: (v) => setState(() => _timeWell = v.round())),
      const SizedBox(height: 10),
    ];
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    final isFollowup = _followup != null;
    final q = isFollowup ? _followup! : _question;
    await CheckinRepo.save(
      question: q,
      answer: _answer.text.trim(),
      mood: isFollowup ? _mood : _mood,
      focus: _focus,
      timeWellSpent: _timeWell,
    );
    if (!isFollowup) {
      await CheckinRepo.rememberQuestionIndex(Db.today(), _questionIndex);
    }

    // Optional ONE follow-up from the LLM, respecting the 4-question cap.
    if (!isFollowup &&
        await CheckinRepo.answeredTonight(Db.today()) <
            CheckinRepo.maxQuestionsPerNight) {
      final fu = await _maybeFollowup();
      if (mounted && fu != null) {
        setState(() {
          _followup = fu;
          _answer.clear();
          _saving = false;
        });
      } else if (mounted) {
        // Offline or capped: queue the dashboard pass for later.
        await queueFollowUpRebuild(Db.today());
        await Db.kvSet('pending_rebuild', '1');
        await _finish();
      }
    } else if (mounted) {
      await Db.kvSet('pending_rebuild', '1');
    }
    if (isFollowup) {
      await _finish();
    }
  }

  /// Asks the LLM for one follow-up question. Any failure simply ends the
  /// night (the app works fully offline).
  Future<String?> _maybeFollowup() async {
    try {
      final llm = LlmService();
      final config = await llm.loadConfig();
      if (!config.apiKeySet) return null;
      final profile = await ProfileRepo.current();
      final nights = await CheckinRepo.lastNights(1);
      return llm.complete<String>(
        config: config,
        system: 'You ask one kind, specific follow-up question at a night\'s '
            'check-in. Reply with ONLY the question.',
        prompt: Prompts.checkinFollowUp(
          profileText: profile,
          answered: [for (final n in nights) n['answer'] as String],
          answeredCount: nights.length,
        ),
        maxOutputTokens: 120,
        parse: (t) {
          final s = t.trim().split('\n').first.trim();
          if (s.isEmpty) throw const FormatException('empty');
          if (s.length > 140) throw const FormatException('too long');
          return s;
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _skipTonight() async {
    await Db.kvSet('checkin_state_${Db.today()}', 'skipped');
    if (!mounted) return;
    setState(() {
      _doneMessage = 'Skipped for tonight. The threshold is always tomorrow.';
    });
  }

  Future<void> _finish() async {
    // Attempt the dashboard pass when online (respecting the spend cap).
    await Db.kvSet('pending_rebuild', '1');
    if (mounted) {
      setState(() {
        _doneMessage =
            'Done for tonight.\n\nTomorrow brings a new question.';
      });
    }
    await _triggerRebuildQuiet();
  }

  Future<void> _triggerRebuildQuiet() async {
    try {
      final llm = LlmService();
      final config = await llm.loadConfig();
      if (!config.apiKeySet) return;
      final profile = await ProfileRepo.current();
      await DashboardRepo.rebuild(
          llm: llm, config: config, profileText: profile, weekly: false);
      await Db.kvDelete('pending_rebuild');
    } catch (_) {
      // Offline / capped: the queued flag makes the next online moment fix up.
    }
  }

  Widget _wrapDone(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Playfair Display',
                fontSize: 28,
                height: 1.35,
                color: GCol.text,
              ),
            ),
            const SizedBox(height: 30),
            BigButton(
              label: 'Good night',
              onTap: () {
                setState(() {
                  _doneMessage = null;
                  _followup = null;
                  _answer.clear();
                  _loading = true;
                });
                _init();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared dark stage for the nightly side of the app.
class _NightSide extends StatelessWidget {
  const _NightSide({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GCol.bg,
      body: Stack(children: [
        const Positioned.fill(child: GoldGlow()),
        const Positioned.fill(child: GrainOverlay()),
        SafeArea(child: child),
      ]),
    );
  }
}
