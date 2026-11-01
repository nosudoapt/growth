import 'package:flutter/material.dart';

/// Motion orchestration. If the system "reduce motion" / remove animations
/// accessibility setting is on, every effect degrades to a simple fade.
class Motion {
  const Motion._();

  /// Is the reduce-motion accessibility setting active?
  static bool isReduced(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  /// Card entrance: fade + rise 16px over 350ms (ease-out-cubic), or plain
  /// fade when reduced motion is on.
  static Widget entrance(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    if (isReduced(context)) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.linear),
        child: child,
      );
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.055),
        end: Offset.zero,
      ).animate(CurvedAnimation(
          parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
  }
}

/// Staggered word reveal for thoughts: each word fades in 20ms after the
/// previous one, over 900ms total (or instantly-faded when reduced).
class WordStagger extends StatelessWidget {
  const WordStagger({
    super.key,
    required this.text,
    required this.controller,
    required this.style,
    this.totalMs = 900,
    this.staggerMs = 20,
  });

  final String text;
  final AnimationController controller;
  final TextStyle style;
  final int totalMs;
  final int staggerMs;

  @override
  Widget build(BuildContext context) {
    final words = text.split(RegExp(r'\s+'));
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) return Text(text, style: style);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final elapsedMs = controller.value * totalMs;
        final spans = <TextSpan>[];
        for (var i = 0; i < words.length; i++) {
          final t = ((elapsedMs - i * staggerMs) / 280).clamp(0.0, 1.0);
          spans.add(TextSpan(
            text: words[i],
            style: style.copyWith(
                color: style.color?.withValues(alpha: t * 0.999 + 0.001)),
          ));
          if (i != words.length - 1) {
            spans.add(const TextSpan(text: ' '));
          }
        }
        return Text.rich(
          TextSpan(children: spans),
          style: style,
        );
      },
    );
  }
}
