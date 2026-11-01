import 'package:flutter_test/flutter_test.dart';
import 'package:growth/logic/eval_logic.dart';

void main() {
  group('EvalScoring', () {
    test('agreement counts ±1 as a hit', () {
      final pairs = [(5, 4), (2, 2), (1, 3), (4, 5)];
      expect(EvalScoring.agreementPct(pairs), closeTo(0.75, 1e-9));
    });

    test('mae is the mean absolute error', () {
      final pairs = [(5, 4), (1, 2)];
      expect(EvalScoring.mae(pairs), 1.0);
    });

    test('empty set reports zero safely', () {
      expect(EvalScoring.agreementPct(const []), 0.0);
      expect(EvalScoring.mae(const []), 0.0);
    });
  });
}
