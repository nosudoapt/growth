import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../repos/evals.dart';
import '../repos/llm.dart';
import '../repos/prompts.dart' show Prompts;
import 'widgets.dart';

/// Eval screen: rate 50 bundled items once, then run them through the
/// current ranking prompt and compare with the user's ratings.
class EvalPage extends StatefulWidget {
  const EvalPage({super.key});

  @override
  State<EvalPage> createState() => _EvalPageState();
}

class _EvalPageState extends State<EvalPage> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _runs = [];
  bool _running = false;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await EvalRepo.ensureSeeded();
    final items = await EvalRepo.items();
    final runs = await EvalRepo.runs();
    if (!mounted) return;
    setState(() {
      _items = items;
      _runs = runs;
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lastResult = null;
    });
    try {
      final llm = LlmService();
      final LlmConfig config = await llm.loadConfig();
      if (!config.apiKeySet) {
        if (mounted) {
          setState(() {
            _running = false;
            _lastResult = 'Add your API key in Settings first.';
          });
        }
        return;
      }
      final (agree, mae) = await EvalRepo.run(llm: llm, config: config);
      if (!mounted) return;
      setState(() {
        _lastResult =
            'Agreement: ${(agree * 100).toStringAsFixed(0)}% • MAE: ${mae.toStringAsFixed(2)} '
            '(${Prompts.rankingVersion})';
      });
      await _load();
    } on SpendBlocked {
      if (mounted) {
        setState(() {
          _running = false;
          _lastResult = calmError(const SpendBlocked());
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _running = false;
          _lastResult = 'The eval could not run right now. Try again later.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GCol.bg,
      appBar: AppBar(
          title: const Text('Eval set',
              style: TextStyle(
                  fontFamily: 'Playfair Display',
                  fontSize: 24,
                  color: GCol.text))),
      body: Stack(children: [
        const Positioned.fill(child: GrainOverlay()),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rate these 50 readings once. "Run eval" asks '
                        'your model to rank the same items and reports how '
                        'well it agrees with you — stored with the prompt '
                        'version so you can compare future prompt changes.',
                        style: const TextStyle(
                            fontSize: 16, height: 1.5, color: GCol.muted)),
                    const SizedBox(height: 14),
                    if (_lastResult != null)
                      Text(_lastResult!,
                          style: const TextStyle(
                              fontSize: 16, color: GCol.gold)),
                    BigButton(label: _running ? 'Running…' : 'Run eval', onTap: _running ? null : _run),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  padding:
                      const EdgeInsets.only(bottom: 24, left: 20, right: 20),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final rating = item['user_rating'] as int?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item['title']}',
                              style: const TextStyle(
                                  fontSize: 16, color: GCol.text)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var s = 1; s <= 5; s++)
                                ChoiceChip(
                                  label: Text('$s'),
                                  selected: rating == s,
                                  labelStyle: TextStyle(
                                      fontSize: 15,
                                      color: rating == s
                                          ? GCol.bg
                                          : GCol.muted),
                                  onSelected: (_) async {
                                    await EvalRepo.rate(item['id'] as int, s);
                                    _load();
                                  },
                                ),
                              if (item['model_rating'] != null)
                                Text('model: ${item['model_rating']}',
                                    style: const TextStyle(
                                        fontSize: 15, color: GCol.muted)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_runs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Past runs',
                          style: TextStyle(
                              fontFamily: 'Playfair Display',
                              fontSize: 20,
                              color: GCol.text)),
                      const SizedBox(height: 8),
                      for (final r in _runs.take(5))
                        Text(
                            '${DateTime.fromMillisecondsSinceEpoch(r['ts'] as int).toIso8601String().substring(0, 16)} '
                            '— ${((((r['agreement_pct'] as num?) ?? 0)) * 100).toStringAsFixed(0)}% agreement, '
                            'MAE ${(r['mae'] as num? ?? 0).toStringAsFixed(2)}, prompt ${r['prompt_version']}',
                            style: const TextStyle(
                                fontSize: 15, color: GCol.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
