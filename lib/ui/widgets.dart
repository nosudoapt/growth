import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/theme.dart';

/// Slow gold radial glow behind each card, 8s loop (skipped for reduce
/// motion — replaced with a static glow).
class GoldGlow extends StatefulWidget {
  const GoldGlow({super.key, this.intense = false});

  final bool intense;

  @override
  State<GoldGlow> createState() => _GoldGlowState();
}

class _GoldGlowState extends State<GoldGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.isReduced(context);
    if (reduced) {
      return _glow(0.55);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _glow(0.4 + 0.25 * math.sin(_c.value * 2 * math.pi)),
    );
  }

  Widget _glow(double strength) {
    final base = widget.intense ? 0.16 : 0.08;
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.4),
            radius: 1.15,
            colors: [
              GCol.gold.withValues(alpha: base * strength),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtle grain overlay (bundled noise PNG, tiled, very low alpha).
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key, this.opacity = 0.05});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          'assets/grain.png',
          repeat: ImageRepeat.repeat,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}

/// Right-side action rail button (≥48dp tap target, icon + helper label).
class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.count,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final color = active ? GCol.gold : GCol.text;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              if (count != null)
                Text('$count',
                    style: const TextStyle(
                        fontSize: 15, color: GCol.muted, fontWeight: FontWeight.w600))
              else
                Text(label,
                    style: const TextStyle(fontSize: 13, color: GCol.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Source tag, bottom-left.
class SourceTag extends StatelessWidget {
  const SourceTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GCol.gold.withValues(alpha: .35)),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15, color: GCol.text, fontWeight: FontWeight.w500)),
    );
  }
}

/// Calm one-tap friend: big gold button used across flows.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: secondary ? GCol.surface : GCol.gold,
            foregroundColor: secondary ? GCol.text : GCol.bg,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      ),
    );
  }
}

/// Gold heart burst (450ms, particles) for the like action.
class HeartBurst extends StatefulWidget {
  const HeartBurst({super.key, required this.child, required this.onLiked});

  final Widget child;
  final VoidCallback onLiked;

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  void burst() {
    if (Motion.isReduced(context)) {
      widget.onLiked();
      return;
    }
    _c.forward(from: 0);
    widget.onLiked();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            if (_c.value == 0) return const SizedBox.shrink();
            return CustomPaint(
              size: const Size(160, 160),
              isComplex: true,
              painter: _BurstPainter(_c.value),
            );
          },
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: burst,
          child: Transform.scale(
            scale: _c.isAnimating
                ? 1 + 0.3 * math.sin(_c.value * math.pi)
                : 1,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = GCol.gold.withValues(alpha: (1 - t))
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 10; i++) {
      final angle = i * 2 * math.pi / 10;
      final radius = t * 55;
      final p = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(p, 3.2 * (1 - t) + 1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.t != t;
}
