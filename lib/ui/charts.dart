import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Line chart, drawn left-to-right over 800ms (respects reduce-motion via a
/// 1-frame "full" state when the parent disables animations).
class TrendLineChart extends StatefulWidget {
  const TrendLineChart({
    super.key,
    required this.values,
    this.maxValue = 5,
    this.color = GCol.gold,
    this.label = '',
  });

  final List<double> values;
  final double maxValue;
  final Color color;
  final String label;

  @override
  State<TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<TrendLineChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) {
      return CustomPaint(
          size: const Size(double.infinity, 140),
          painter: _LinePainter(widget.values, widget.color, 1.0, widget.maxValue, widget.label));
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: const Size(double.infinity, 140),
        painter: _LinePainter(widget.values, widget.color, _c.value, widget.maxValue, widget.label),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.values, this.color, this.progress, this.max, this.label);

  final List<double> values;
  final Color color;
  final double progress;
  final double max;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const pad = 14.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final stepX = values.length > 1 ? w / (values.length - 1) : 0.0;

    Offset at(int i) => Offset(
        pad + i * stepX,
        pad + h - (values[i].clamp(0, max) / max) * h);

    final upTo = ((values.length - 1) * progress).floor();
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i <= upTo; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    // The currently-drawing segment (partial, eased).
    if (progress < 1.0 && upTo < values.length - 1) {
      final a = at(upTo);
      final b = at(upTo + 1);
      final f = ((values.length - 1) * progress) - upTo;
      path.lineTo(a.dx + (b.dx - a.dx) * f, a.dy + (b.dy - a.dy) * f);
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    // Soft area fill under the line.
    final area = Path.from(path)
      ..lineTo(size.width - pad, size.height - pad)
      ..lineTo(pad, size.height - pad)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    canvas.drawPath(path, line);

    // Dots.
    final dot = Paint()..color = color;
    for (var i = 0; i <= upTo; i++) {
      canvas.drawCircle(at(i), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.values != values;
}

/// Bar chart for reading minutes per day (drawn with the same easing idea).
class MinuteBarChart extends StatelessWidget {
  const MinuteBarChart({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final max = values.fold(1.0, math.max);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: (v / max).clamp(0.02, 1.0),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      color: GCol.gold.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: GCol.gold.withValues(alpha: .6)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
