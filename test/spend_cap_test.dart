import 'package:flutter_test/flutter_test.dart';
import 'package:growth/logic/spend_cap.dart';

void main() {
  group('SpendCap', () {
    test('token estimate uses chars/4 + max output', () {
      // 40 chars input → 10 input tokens; + 20 max output.
      expect(SpendCap.estimateTokens('x' * 40, '', 20), 30);
      // System prompt included in the estimate.
      expect(SpendCap.estimateTokens('x' * 40, 'y' * 40, 0), 20);
    });

    test('estimateUsd scales with price per 1k', () {
      expect(SpendCap.estimateUsd(1000, 0.003), closeTo(0.003, 1e-9));
      expect(SpendCap.estimateUsd(500, 0.004), closeTo(0.002, 1e-9));
    });

    test('monthKey resets monthly', () {
      expect(SpendCap.monthKey(DateTime(2026, 11, 2)), '2026-11');
      expect(SpendCap.monthKey(DateTime(2026, 12, 31)), '2026-12');
      expect(SpendCap.monthKey(DateTime(2027, 1, 1)), '2027-01');
    });

    test('cap blocks beyond the limit and allows just under', () {
      expect(
        SpendCap.willExceed(
            currentMonthUsd: 4.99, callEstimateUsd: 0.02, monthlyCapUsd: 5.0),
        isTrue,
      );
      expect(
        SpendCap.willExceed(
            currentMonthUsd: 4.98, callEstimateUsd: 0.01, monthlyCapUsd: 5.0),
        isFalse,
      );
      expect(
        SpendCap.willExceed(
            currentMonthUsd: 0, callEstimateUsd: 5.0, monthlyCapUsd: 5.0),
        isFalse,
      ); // exactly the cap is allowed
      expect(
        SpendCap.willExceed(
            currentMonthUsd: 0, callEstimateUsd: 5.01, monthlyCapUsd: 5.0),
        isTrue,
      );
    });
  });
}
