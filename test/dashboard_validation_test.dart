import 'package:flutter_test/flutter_test.dart';
import 'package:growth/domain/dashboard.dart';

void main() {
  group('dashboard JSON validation', () {
    test('accepts a fully valid dashboard payload', () {
      expect(
        validateDashboard(_valid()),
        isEmpty,
      );
    });

    test('rejects a bad trend value', () {
      final m = _valid();
      (m['focus_trend'] as List).first['value'] = 9;
      expect(validateDashboard(m), isNotEmpty);
    });

    test('rejects a bad date shape', () {
      final m = _valid();
      (m['mood_trend'] as List).first['date'] = 'nope';
      expect(validateDashboard(m), isNotEmpty);
    });

    test('rejects non-clinical bad-habit bad shape (missing fields)', () {
      final m = _valid();
      m['bad_habits'] = [
        {'name': 'late scrolling'}
      ];
      expect(validateDashboard(m), isNotEmpty);
    });

    test('rejects favorites with wrong type', () {
      final m = _valid();
      m['favorites'] = [
        {'name': 'Stoicism', 'type': 'vibe', 'likes': 3, 'why': 'x'}
      ];
      expect(validateDashboard(m), isNotEmpty);
    });

    test('rejects progress entries missing note', () {
      final m = _valid();
      m['progress'] = [
        {'metric': 'reading', 'this_week': 3, 'last_week': 1}
      ];
      expect(validateDashboard(m), isNotEmpty);
    });

    test('rejects missing top-level keys', () {
      final m = _valid();
      m.remove('win_of_the_week');
      expect(validateDashboard(m), isNotEmpty);
    });

    test('accepts next_question null', () {
      final m = _valid();
      m['next_question'] = null;
      expect(validateDashboard(m), isEmpty);
    });

    test('extractJsonObject strips fences and preambl', () {
      final raw = '''
Here you go:
```json
{"focus_trend": [], "weekly_suggestion": "keep going"}
```
''';
      final obj = extractJsonObject(raw);
      expect(obj['weekly_suggestion'], 'keep going');
    });
  });
}

Map<String, dynamic> _valid() => {
      'focus_trend': [
        {'date': '2026-11-02', 'value': 3}
      ],
      'mood_trend': [
        {'date': '2026-11-02', 'value': 4}
      ],
      'time_well_spent_trend': [
        {'date': '2026-11-02', 'value': 2}
      ],
      'weekly_suggestion': 'Read before sleep, after simran.',
      'reading': {
        'minutes_by_day': [
          {'date': '2026-11-02', 'minutes': 12.5}
        ],
        'streak': 3,
        'longest_streak': 5,
        'finished_by_topic': {'Philosophy': 2},
      },
      'favorites': [
        {'name': 'Daily Stoic', 'type': 'source', 'likes': 4, 'why': 'Short, sharp.'}
      ],
      'good_habits': [
        {'name': 'Nightly check-in', 'consistency_pct': 86.0, 'note': 'Reliable.'}
      ],
      'bad_habits': [
        {
          'name': 'Evening scroll after 23:00',
          'pattern': 'Reaches for the phone in bed',
          'gentle_alternative': 'Charge the phone outside reach.',
        }
      ],
      'progress': [
        {'metric': 'minutes read', 'this_week': 42, 'last_week': 20, 'note': 'Double.'}
      ],
      'win_of_the_week': 'Five nights checked in.',
      'next_question': null,
    };
