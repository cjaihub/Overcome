import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand.dart';

enum StepIconMotion { pulse, orbit, wave, rise, breathe }

/// Premium animated glyph: a glowing gradient orb with an icon and a
/// motion layer (orbiting particles, sound waves, breathing ring …)
/// chosen per screen.
class AnimatedStepIcon extends StatefulWidget {
  const AnimatedStepIcon({
    super.key,
    required this.icon,
    this.motion = StepIconMotion.pulse,
    this.color = Brand.aurora,
    this.size = 96,
  });

  final IconData icon;
  final StepIconMotion motion;
  final Color color;
  final double size;

  @override
  State<AnimatedStepIcon> createState() => _AnimatedStepIconState();
}

class _AnimatedStepIconState extends State<AnimatedStepIcon> with TickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void didUpdateWidget(AnimatedStepIcon old) {
    super.didUpdateWidget(old);
    if (old.icon != widget.icon) _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s * 1.5,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _enter]),
        builder: (context, _) {
          final enter = Curves.elasticOut.transform(_enter.value);
          return CustomPaint(
            painter: _MotionPainter(widget.motion, _loop.value, widget.color, s),
            child: Center(
              child: Transform.scale(
                scale: 0.4 + 0.6 * enter,
                child: Transform.rotate(
                  angle: (1 - enter) * -0.6,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [widget.color, Color.lerp(widget.color, Brand.iris, 0.6)!],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.45 + 0.15 * math.sin(_loop.value * 2 * math.pi)),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: s * 0.46),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MotionPainter extends CustomPainter {
  _MotionPainter(this.motion, this.t, this.color, this.size);
  final StepIconMotion motion;
  final double t;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size box) {
    final c = box.center(Offset.zero);
    final r = size / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color.withValues(alpha: 0.5);
    final dot = Paint()..color = color;
    final a = t * 2 * math.pi;

    switch (motion) {
      case StepIconMotion.pulse:
        for (var i = 0; i < 3; i++) {
          final p = (t + i / 3) % 1;
          canvas.drawCircle(c, r + p * r * 0.55, stroke..color = color.withValues(alpha: (1 - p) * 0.5));
        }
      case StepIconMotion.orbit:
        canvas.drawCircle(c, r * 1.3, stroke..color = color.withValues(alpha: 0.18));
        for (var i = 0; i < 3; i++) {
          final ang = a + i * 2 * math.pi / 3;
          canvas.drawCircle(c + Offset(math.cos(ang), math.sin(ang)) * r * 1.3, 4 - i.toDouble(), dot);
        }
      case StepIconMotion.wave:
        for (var side = -1; side <= 1; side += 2) {
          for (var i = 0; i < 4; i++) {
            final h = (0.3 + 0.7 * ((math.sin(a * 2 + i) + 1) / 2)) * r * 0.7;
            final x = c.dx + side * (r + 10 + i * 9);
            canvas.drawLine(
              Offset(x, c.dy - h / 2),
              Offset(x, c.dy + h / 2),
              Paint()
                ..color = color.withValues(alpha: 0.7 - i * 0.14)
                ..strokeWidth = 4
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      case StepIconMotion.rise:
        for (var i = 0; i < 6; i++) {
          final p = (t + i / 6) % 1;
          final x = c.dx + math.sin(i * 1.7) * r * 0.9;
          final y = c.dy + r * 1.1 - p * r * 2.4;
          canvas.drawCircle(Offset(x, y), 3, dot..color = color.withValues(alpha: (1 - p) * 0.9));
        }
      case StepIconMotion.breathe:
        final s = 1 + 0.18 * math.sin(a);
        canvas.drawCircle(c, r * 1.18 * s, Paint()..color = color.withValues(alpha: 0.12));
        canvas.drawCircle(c, r * 1.35 * s, stroke..color = color.withValues(alpha: 0.25));
    }
  }

  @override
  bool shouldRepaint(_MotionPainter old) => true;
}
