import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// Slow-moving gradient orbs behind every screen. Each page passes its own
/// [accent] so the mood shifts with the content.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child, this.accent = Brand.aurora});

  final Widget child;
  final Color accent;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: widget.accent),
            duration: Brand.motionSlow,
            builder: (context, accent, _) => AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _AuroraPainter(
                  t: reduceMotion ? 0.2 : _c.value,
                  accent: accent ?? widget.accent,
                  base: Theme.of(context).scaffoldBackgroundColor,
                  intensity: dark ? 0.32 : 0.18,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.t, required this.accent, required this.base, required this.intensity});
  final double t;
  final Color accent;
  final Color base;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final a = t * 2 * math.pi;
    void orb(Color c, double cx, double cy, double r) {
      final center = Offset(size.width * cx, size.height * cy);
      canvas.drawCircle(
        center,
        r * size.width,
        Paint()
          ..shader = RadialGradient(
            colors: [
              c.withValues(alpha: intensity),
              c.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r * size.width)),
      );
    }

    orb(accent, 0.2 + 0.1 * math.sin(a), 0.12 + 0.05 * math.cos(a), 0.9);
    orb(Brand.iris, 0.9 + 0.08 * math.cos(a * 0.7), 0.35 + 0.08 * math.sin(a * 0.7), 0.75);
    orb(Color.lerp(accent, Brand.ember, 0.5)!, 0.4 + 0.12 * math.sin(a * 1.3), 1.0, 0.8);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t || old.accent != accent || old.base != base;
}
