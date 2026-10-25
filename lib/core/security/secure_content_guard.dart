import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/brand.dart';
import 'screen_security.dart';

/// Wraps premium content (PDF pages, read-along text, audiobook artwork).
///
/// * Blanks the content while the screen is being recorded or mirrored.
/// * Tiles a faint, per-user forensic watermark over the content so any
///   photo taken of the screen can be traced back to the account.
/// * Reports screenshot attempts through [onCaptureAttempt].
class SecureContentGuard extends StatefulWidget {
  const SecureContentGuard({super.key, required this.child, required this.watermark, this.onCaptureAttempt});

  final Widget child;

  /// Usually a short account id + masked phone number.
  final String watermark;
  final void Function(String kind)? onCaptureAttempt;

  @override
  State<SecureContentGuard> createState() => _SecureContentGuardState();
}

class _SecureContentGuardState extends State<SecureContentGuard> {
  late bool _captured = ScreenSecurity.instance.isCaptured;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(
        ScreenSecurity.instance.capturedChanges.listen((c) {
          setState(() => _captured = c);
          if (c) widget.onCaptureAttempt?.call('recording');
        }),
      )
      ..add(
        ScreenSecurity.instance.screenshotAttempts.listen((_) {
          widget.onCaptureAttempt?.call('screenshot');
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Protected content cannot be captured.')));
        }),
      );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stamp = '${widget.watermark} · ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}';
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _WatermarkPainter(stamp, Theme.of(context).colorScheme.onSurface)),
          ),
        ),
        if (_captured)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: ColoredBox(
                  color: Brand.ink.withValues(alpha: 0.92),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_moon_rounded, color: Brand.aurora, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          'Screen capture detected',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Stop recording or mirroring to keep reading.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter(this.text, this.color);
  final String text;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color.withValues(alpha: 0.06), fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 7);
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final stepX = tp.width + 48;
    const stepY = 72.0;
    var row = 0;
    for (var y = -diag / 2; y < diag / 2; y += stepY, row++) {
      final offset = row.isEven ? 0.0 : stepX / 2;
      for (var x = -diag / 2 - offset; x < diag / 2; x += stepX) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) => old.text != text || old.color != color;
}
