/// Token + spend estimation for the user's own LLM API key.
///
/// The app never calls our own service; it calls whatever endpoint the user
/// configured. This module estimates tokens per call (chars/4 for input,
/// maxTokens for output), converts to a running USD estimate, and answers
/// whether the monthly cap blocks the call.
class SpendCap {
  const SpendCap._();

  static const int charsPerToken = 4;

  /// Rough token estimate for one call.
  static int estimateTokens(String promptText, String systemText, int maxOutputTokens) {
    final inputChars = promptText.length + systemText.length;
    final inputTokens = (inputChars / charsPerToken).ceil();
    return inputTokens + maxOutputTokens;
  }

  /// Convert tokens to an USD estimate using a configured per-1k-token price.
  static double estimateUsd(int tokens, double pricePer1k) =>
      tokens * pricePer1k / 1000.0;

  /// Month key like "2026-11" for resetting the running estimate.
  static String monthKey(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

  /// A blocking decision given current month usage and configured cap.
  /// Returns true when spending would exceed the cap.
  static bool willExceed({
    required double currentMonthUsd,
    required double callEstimateUsd,
    required double monthlyCapUsd,
  }) =>
      currentMonthUsd + callEstimateUsd > monthlyCapUsd;
}
