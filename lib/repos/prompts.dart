/// Prompt contracts. Versions are stored with eval results for comparison.
class Prompts {
  const Prompts._();

  static const String dashboardVersion = 'dashboard-v1';
  static const String rankingVersion = 'ranking-v1';

  static String get _tone {
    return '''
You are Growth, a calm, kind, non-judgmental companion for one person's
self-improvement. Non-diagnostic always: patterns, never labels. Plain short
sentences. No emoji. No moralizing. Respect goals like reducing anger and
ego, deepening connection with Nirankar (the Formless One), reading more,
wasting less time. Plain text.''';
  }

  /// Thought of the day: at most 2 sentences, drawn from the profile.
  static String thoughtOfDay(String profileText) {
    return '''
A short daily thought (maximum 2 sentences) for the person described in the
profile below. Grounded in self-improvement, Stoic and Greek/Roman
philosophy, Socratic method, Munger's mental models, cognitive biases,
emotional intelligence, habit formation, sleep, or Sikh practice (Nam
Simran, gratitude, stillness). It must feel personal and actionable, quiet
rather than motivational-poster. Reply with ONLY the thought in plain text,
no quotes, no heading, no explanation.

PROFILE:
$profileText''';
  }

  static String thoughtSystem() {
    return '$_tone\nHARD RULE: reply must be 1 or 2 sentences of plain text. '
        'If you cannot, the request fails validation.';
  }

  /// The nightly follow-up: ONE question chosen from the answers.
  static String checkinFollowUp({
    required String profileText,
    required List<String> answered,
    required int answeredCount,
  }) {
    return '''
Read tonight's answers and ask exactly ONE gentle follow-up question — the
single most insightful next question for this person, chosen from the
answers (not generic). Max 25 words. Plain text only, no quotes.

PROFILE (abridged):
$profileText

TONIGHT ($answeredCount answers):
${answered.mapIndexed((i, a) => 'Q${i + 1}: $a').join('\n')}''';
  }

  /// Dashboard rebuild prompt with the strict JSON schema.
  static String dashboard({
    required String profileText,
    required List<String> last7CheckinsJson,
    required Map<String, double> minutesByDay,
    required List<String> likedTitles,
    required List<String> skippedTitles,
    required bool weeklyRebuild,
  }) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '''
Produce a weekly reflection JSON. ${weeklyRebuild ? 'This is the full weekly rebuild (last 7 days).' : 'Incremental update (carry forward, adjust today).'}

STRICT JSON SCHEMA (reply with ONLY this JSON):
{
  "focus_trend": [{"date":"YYYY-MM-DD","value":1}],
  "mood_trend": [same shape],
  "time_well_spent_trend": [same shape],
  "weekly_suggestion": "string",
  "reading": {"minutes_by_day":[{"date":"","minutes":0}],"streak":0,"longest_streak":0,"finished_by_topic":{}},
  "favorites": [{"name":"","type":"topic|source|author","likes":0,"why":""}],
  "good_habits": [{"name":"","consistency_pct":number,"note":""}],
  "bad_habits": [{"name":"","pattern":"","gentle_alternative":""}],
  "progress": [{"metric":"","this_week":0,"last_week":0,"note":""}],
  "win_of_the_week": "string",
  "next_question": "string or null"
}
Rules: trend values are ints 1..5; when a day has no data, OMIT that day
rather than inventing a value. minutes: numbers. streaks: ints.
bad_habits.name must be a pattern, NOT a diagnosis (no clinical or
personality terms, no medical words). No extra keys. No prose outside the
JSON.

DATA (today is $today):
PROFILE:
$profileText

CHECK-INS LAST 7 DAYS (JSON):
${last7CheckinsJson.join('\n')}

READING MINUTES BY DAY:
${minutesByDay.keys.map((d) => "$d: ${minutesByDay[d]!.toStringAsFixed(1)}").join('\n')}

LIKED:
${likedTitles.take(50).join('\n')}

SKIPPED:
${skippedTitles.take(50).join('\n')}''';
  }

  static String ranking(String items) {
    return '''
Rate each item below 1 to 5 for its value to a person practicing
self-improvement through reading: Stoicism, Greek and Roman philosophy,
Socratic method, mental models (Charlie Munger), Naval Ravikant's writing,
cognitive biases, emotional intelligence, habit formation, sleep, and Sikh
practice (Nam Simran, gratitude, stillness). 1 = skip entirely, 3 = decent
evening read, 5 = reread-worthy. Reply with ONLY JSON:
{"ratings":[{"id":1,"score":3}, ...]} — one entry per item id, no extra keys.

ITEMS:
$items''';
  }
}

/// Tiny helper used in prompts: mapIndexed for lists of strings.
extension StringListMapIndexed on List<String> {
  List<String> mapIndexed(String Function(int, String) f) {
    final out = <String>[];
    for (var i = 0; i < length; i++) {
      out.add(f(i, this[i]));
    }
    return out;
  }
}
