import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../theme/brand.dart';

/// Number that counts up/down to [value] whenever it changes.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({super.key, required this.value, this.style, this.suffix = '', this.decimals = 0});

  final double value;
  final TextStyle? style;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPatternDigits(decimalDigits: decimals);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: Brand.motionSlow,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${fmt.format(v)}$suffix', style: style),
    );
  }
}

/// Circular progress gauge with a gradient sweep and centered label.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.progress,
    required this.center,
    this.caption,
    this.size = 150,
    this.color = Brand.aurora,
  });

  final double progress;
  final Widget center;
  final String? caption;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: progress.clamp(0, 1)),
          duration: Brand.motionSlow,
          curve: Curves.easeOutCubic,
          builder: (context, p, child) => CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(p, color, track),
            child: SizedBox.square(
              dimension: size,
              child: Center(child: child),
            ),
          ),
          child: center,
        ),
        if (caption != null) ...[
          const SizedBox(height: 8),
          Text(caption!, style: Theme.of(context).textTheme.labelMedium),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.color, this.track);
  final double p;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.09;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (p <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [color, Color.lerp(color, Brand.iris, 0.7)!, color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.p != p || old.color != color;
}

/// Horizontal animated bars — e.g. "where your attention goes".
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.values, this.maxValue});

  final Map<String, double> values;
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    final max = maxValue ?? values.values.fold<double>(1, math.max);
    final colors = Brand.accents.values.toList();
    final text = Theme.of(context).textTheme;
    final entries = values.entries.toList();
    if (entries.isEmpty) {
      return Text(
        'Select what pulls you in to see it mapped here.',
        style: text.bodySmall,
        textAlign: TextAlign.center,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(entries[i].key, style: text.labelMedium, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(entries[i].key),
                    tween: Tween(begin: 0, end: entries[i].value / max),
                    duration: Duration(milliseconds: 600 + i * 90),
                    curve: Curves.easeOutBack,
                    builder: (context, v, _) => Stack(
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: v.clamp(0.02, 1),
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [colors[i % colors.length], Brand.iris]),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Animated area chart used for trends and projections.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.color = Brand.aurora, this.height = 140, this.labels});

  final List<double> points;
  final Color color;
  final double height;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i])];
    final maxY = points.isEmpty ? 1.0 : points.reduce(math.max) * 1.2 + 0.01;
    return SizedBox(
      height: height,
      child: LineChart(
        duration: Brand.motionSlow,
        curve: Curves.easeOutCubic,
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: true),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: labels != null,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (labels == null || i < 0 || i >= labels!.length) return const SizedBox.shrink();
                  return Text(labels![i], style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5)));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              barWidth: 3,
              color: color,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating bubbles sized by weight — used for triggers / emotions.
class BubbleCloud extends StatefulWidget {
  const BubbleCloud({super.key, required this.items, this.height = 160});
  final List<String> items;
  final double height;

  @override
  State<BubbleCloud> createState() => _BubbleCloudState();
}

class _BubbleCloudState extends State<BubbleCloud> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Brand.accents.values.toList();
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          if (widget.items.isEmpty) {
            return Center(child: Text('Your triggers will float here', style: Theme.of(context).textTheme.bodySmall));
          }
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              children: [
                for (var i = 0; i < widget.items.length; i++) _bubble(i, box.biggest, colors[i % colors.length]),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bubble(int i, Size box, Color color) {
    // Up to 7 bubbles on an outer ellipse, the rest on an inner one (or a
    // single bubble in the centre), so labels never overlap.
    final n = widget.items.length;
    final outer = math.min(n, 7);
    final onOuter = i < outer;
    final ringCount = onOuter ? outer : n - outer;
    final slot = onOuter ? i : i - outer;
    final d = onOuter ? 58.0 : 50.0;
    final scale = n == 1 ? 0.0 : (onOuter ? 1.0 : (ringCount == 1 ? 0.0 : 0.42));
    final angle = -math.pi / 2 + slot * 2 * math.pi / ringCount + (onOuter ? 0 : math.pi / ringCount);
    final rx = (box.width / 2 - d / 2 - 4) * math.min(1, 0.45 + n * 0.08) * scale;
    final ry = (box.height / 2 - d / 2 - 4) * scale;
    final wobble = math.sin(_c.value * 2 * math.pi + i) * 4;
    final x = box.width / 2 + math.cos(angle) * rx - d / 2;
    final y = box.height / 2 + math.sin(angle) * ry - d / 2 + wobble;
    return AnimatedPositioned(
      key: ValueKey(widget.items[i]),
      duration: Brand.motion,
      curve: Curves.easeOutBack,
      left: x,
      top: y,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Brand.motion,
        curve: Curves.elasticOut,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Text(
            widget.items[i],
            textAlign: TextAlign.center,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
          ),
        ),
      ),
    );
  }
}
