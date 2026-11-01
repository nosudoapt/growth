/// Profile word limit.
const int kProfileMaxWords = 800;

/// Seed goals (editable in settings).
const List<String> kSeedGoals = <String>[
  'reduce anger',
  'reduce ego-driven reactions',
  'deepen connection with Nirankar',
  'read more',
  'waste less time',
];

int wordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// Compiles the user's local profile text from raw signals. Deterministic so
/// it is testable; the LLM rewrites it weekly if available.
String compileProfile({
  required List<String> goals,
  required List<String> likedTopics,
  required List<String> skippedTopics,
  required List<String> checkinThemes,
  String? preferredReadLength,
}) {
  final buf = StringBuffer();

  if (goals.isNotEmpty) {
    buf.writeln('Goals: ${goals.join(', ')}.');
  }
  buf.writeln(
      'Note: goals are private. Suggestions, dashboards, and follow-ups '
      'should serve these goals, not judge the person.');
  if (likedTopics.isNotEmpty) {
    buf.writeln('Liked topics: ${likedTopics.take(40).join(', ')}.');
  }
  if (skippedTopics.isNotEmpty) {
    buf.writeln('Skipped topics: ${skippedTopics.take(40).join(', ')}.');
  }
  if (checkinThemes.isNotEmpty) {
    buf.writeln(
        'Recurring check-in themes: ${checkinThemes.take(20).join(', ')}.');
  }
  if (preferredReadLength != null) {
    buf.writeln('Preferred read length: $preferredReadLength.');
  }
  buf.writeln(
      'Tone: plain, kind, non-diagnostic. Patterns, never labels. Short.');

  final out = buf.toString().trim();
  if (wordCount(out) > kProfileMaxWords) {
    final words = out.split(RegExp(r'\s+'));
    return words.sublist(0, kProfileMaxWords).join(' ');
  }
  return out;
}
