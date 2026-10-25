import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/brand.dart';
import 'book.dart';

/// A true 3D book (front, back, spine and page block) rendered with
/// perspective transforms. Only the faces pointing at the viewer are
/// painted, so the convex box never needs depth sorting.
class Book3D extends StatelessWidget {
  const Book3D({super.key, required this.book, required this.angle, this.width = 200, this.tilt = 0});

  final Book book;

  /// Rotation around the vertical axis, radians.
  final double angle;

  /// Small rotation around the horizontal axis for a "held" feel.
  final double tilt;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = width * 1.5;
    final d = width * 0.16;
    final cos = math.cos(angle);
    final sin = math.sin(angle);

    Matrix4 face(Matrix4 local) => Matrix4.rotationX(tilt).multiplied(Matrix4.rotationY(angle)).multiplied(local);

    final faces = <Widget>[
      if (cos > 0) _face(face(Matrix4.translationValues(0, 0, -d / 2)), w, h, _Cover(book: book, shade: 1 - cos)),
      if (cos < 0)
        _face(
          face(Matrix4.translationValues(0, 0, d / 2).multiplied(Matrix4.rotationY(math.pi))),
          w,
          h,
          _BackCover(book: book, shade: 1 + cos),
        ),
      if (sin < 0)
        _face(
          face(Matrix4.translationValues(-w / 2, 0, 0).multiplied(Matrix4.rotationY(math.pi / 2))),
          d,
          h,
          _Spine(book: book, shade: 1 + sin),
        ),
      if (sin > 0)
        _face(
          face(Matrix4.translationValues(w / 2, 0, 0).multiplied(Matrix4.rotationY(-math.pi / 2))),
          d,
          h,
          _PageBlock(shade: 1 - sin),
        ),
    ];

    return SizedBox(
      width: w * 1.25,
      height: h * 1.15,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft floor shadow that stretches as the book turns.
          Positioned(
            bottom: 0,
            child: Container(
              width: w * (0.7 + 0.25 * sin.abs()),
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [BoxShadow(color: book.color.withValues(alpha: 0.45), blurRadius: 28, spreadRadius: 2)],
              ),
            ),
          ),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..setEntry(3, 2, 0.0011),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: faces),
            ),
          ),
        ],
      ),
    );
  }

  Widget _face(Matrix4 m, double w, double h, Widget child) => Transform(
    alignment: Alignment.center,
    transform: m,
    child: SizedBox(width: w, height: h, child: child),
  );
}

class _Shade extends StatelessWidget {
  const _Shade({required this.shade, required this.child});
  final double shade;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      IgnorePointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: (shade * 0.55).clamp(0, 0.55))),
      ),
    ],
  );
}

class _Cover extends StatelessWidget {
  const _Cover({required this.book, required this.shade});
  final Book book;
  final double shade;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.horizontal(right: Radius.circular(6), left: Radius.circular(2)),
    child: _Shade(
      shade: shade,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: BoxDecoration(gradient: Brand.gradientFor(book.accent))),
          if (book.coverUrl.isNotEmpty)
            Image.network(book.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
          else
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, height: 1.1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.author.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          // Hinge crease + glossy highlight
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x55000000), Color(0x00000000), Color(0x22FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.06, 0.4, 0.7],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BackCover extends StatelessWidget {
  const _BackCover({required this.book, required this.shade});
  final Book book;
  final double shade;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.horizontal(left: Radius.circular(6), right: Radius.circular(2)),
    child: _Shade(
      shade: shade,
      child: Container(
        color: Color.lerp(book.color, Brand.ink, 0.65),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                book.description,
                overflow: TextOverflow.fade,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70, fontSize: 9),
              ),
            ),
            Text(
              Brand.name.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: book.color, letterSpacing: 3),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Spine extends StatelessWidget {
  const _Spine({required this.book, required this.shade});
  final Book book;
  final double shade;

  @override
  Widget build(BuildContext context) => _Shade(
    shade: shade,
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color.lerp(book.color, Colors.black, 0.4)!, book.color]),
      ),
      alignment: Alignment.center,
      child: RotatedBox(
        quarterTurns: 1,
        child: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, letterSpacing: 1.5),
        ),
      ),
    ),
  );
}

class _PageBlock extends StatelessWidget {
  const _PageBlock({required this.shade});
  final double shade;

  @override
  Widget build(BuildContext context) => _Shade(
    shade: shade * 0.6,
    child: CustomPaint(painter: _PagesPainter()),
  );
}

class _PagesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF3EFE6));
    final line = Paint()
      ..color = const Color(0xFFD9D2C3)
      ..strokeWidth = 0.6;
    for (var x = 1.5; x < size.width; x += 2.2) {
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Book the user can spin with a finger; it keeps momentum and settles
/// gently on the cover or the back.
class InteractiveBook3D extends StatefulWidget {
  const InteractiveBook3D({super.key, required this.book, this.width = 220});
  final Book book;
  final double width;

  @override
  State<InteractiveBook3D> createState() => _InteractiveBook3DState();
}

class _InteractiveBook3DState extends State<InteractiveBook3D> with TickerProviderStateMixin {
  late final _spin = AnimationController.unbounded(vsync: this, value: -0.45);
  late final _idle = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
  double _tilt = 0.08;
  int _lastQuadrant = 0;

  @override
  void initState() {
    super.initState();
    _spin.addListener(_hapticTick);
  }

  void _hapticTick() {
    final q = (_spin.value / (math.pi / 2)).floor();
    if (q != _lastQuadrant) {
      _lastQuadrant = q;
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _settle(double velocity) {
    // Fling with friction, then snap to the nearest resting face.
    final friction = FrictionSimulation(0.12, _spin.value, velocity);
    // Resting pose is a three-quarter view so the spine stays visible.
    final target = (friction.finalX / math.pi).roundToDouble() * math.pi - 0.35;
    _spin.animateWith(
      SpringSimulation(const SpringDescription(mass: 1, stiffness: 40, damping: 9), _spin.value, target, velocity),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart: (_) => _spin.stop(),
    onPanUpdate: (d) {
      _spin.value += d.delta.dx * 0.012;
      setState(() => _tilt = (_tilt - d.delta.dy * 0.004).clamp(-0.35, 0.35));
    },
    onPanEnd: (d) {
      setState(() => _tilt = 0.08);
      _settle(d.velocity.pixelsPerSecond.dx * 0.012);
    },
    child: AnimatedBuilder(
      animation: Listenable.merge([_spin, _idle]),
      builder: (context, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: _tilt),
        duration: Brand.motion,
        curve: Curves.easeOutBack,
        builder: (context, tilt, _) => Book3D(
          book: widget.book,
          width: widget.width,
          angle: _spin.value + math.sin(_idle.value * math.pi) * 0.06,
          tilt: tilt,
        ),
      ),
    ),
  );
}
