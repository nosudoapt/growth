/// Eval scoring: how much does the model's 1–5 ranking agree with the user's?
class EvalScoring {
  const EvalScoring._();

  /// Fraction of items where the model's score is within ±1 of the user's.
  static double agreementPct(
    List<(int userRating, int modelRating)> pairs,
  ) {
    if (pairs.isEmpty) return 0.0;
    var hits = 0;
    for (final (u, m) in pairs) {
      if ((u - m).abs() <= 1) hits++;
    }
    return hits / pairs.length;
  }

  /// Mean absolute error between user and model ratings.
  static double mae(List<(int userRating, int modelRating)> pairs) {
    if (pairs.isEmpty) return 0.0;
    var sum = 0.0;
    for (final (u, m) in pairs) {
      sum += (u - m).abs();
    }
    return sum / pairs.length;
  }
}
