import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/services/firebase_providers.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import 'progress_math.dart';
import 'progress_repository.dart';

/// Live progress over the addiction: trends, consistency heatmap,
/// engagement with the library, and the check-in history.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkIns = ref.watch(checkInsProvider).value ?? const <CheckIn>[];
    final stats = (ref.watch(userDocProvider).value?['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final text = Theme.of(context).textTheme;
    final mood30 = ProgressMath.dailyMood(checkIns, days: 30);
    final urges = ProgressMath.countSince(checkIns, const Duration(days: 30), formId: 'urge_log');

    int stat(String k) => (stats[k] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Text('Progress', style: text.headlineMedium),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wellbeing · 30 days', style: text.titleMedium),
              const SizedBox(height: 12),
              TrendChart(points: mood30, height: 160, color: Brand.iris),
            ],
          ),
        ),
        const SectionTitle('Consistency'),
        GlassCard(child: _Heatmap(checkIns: checkIns)),
        const SectionTitle('At a glance'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _Stat('Check-ins', checkIns.length.toDouble(), Icons.edit_note_rounded, Brand.aurora),
            _Stat('Urges logged (30d)', urges.toDouble(), Icons.bolt_rounded, Brand.ember),
            _Stat('Pages read', stat('pdf_page_view').toDouble(), Icons.menu_book_rounded, Brand.iris),
            _Stat('Audio sessions', stat('audio_play').toDouble(), Icons.headphones_rounded, Brand.bloom),
            _Stat('App sessions', stat('app_open').toDouble(), Icons.touch_app_rounded, Brand.success),
            _Stat('Minutes in app', (stat('session_seconds') / 60).roundToDouble(), Icons.timer_rounded, Brand.aurora),
          ],
        ),
        const SectionTitle('Recent check-ins'),
        for (final c in checkIns.reversed.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.formId.replaceAll('_', ' '), style: text.titleSmall),
                        Text(DateFormat('EEE d MMM · HH:mm').format(c.at), style: text.bodySmall),
                      ],
                    ),
                  ),
                  if (c.mood != null) Text('${c.mood}', style: text.titleLarge?.copyWith(color: Brand.aurora)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const Spacer(),
        AnimatedCounter(value: value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

/// GitHub-style 12-week heatmap of check-in activity.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.checkIns});
  final List<CheckIn> checkIns;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final counts = <String, int>{};
    for (final c in checkIns) {
      final k = DateFormat('yyyyMMdd').format(c.at);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    const weeks = 12;
    return LayoutBuilder(
      builder: (context, box) {
        final cell = (box.maxWidth - (weeks - 1) * 4) / weeks;
        return SizedBox(
          height: cell * 7 + 24,
          child: Row(
            children: [
              for (var w = weeks - 1; w >= 0; w--) ...[
                Column(
                  children: [
                    for (var d = 6; d >= 0; d--)
                      Builder(
                        builder: (context) {
                          final day = today.subtract(Duration(days: w * 7 + d));
                          final n = counts[DateFormat('yyyyMMdd').format(day)] ?? 0;
                          return Container(
                            width: cell,
                            height: cell,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: n == 0
                                  ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06)
                                  : Brand.aurora.withValues(alpha: (0.3 + n * 0.25).clamp(0, 1)),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                if (w > 0) const SizedBox(width: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}
