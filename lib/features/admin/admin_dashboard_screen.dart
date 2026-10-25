import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import 'admin_repository.dart';

/// Owner view: how many people use the app, how often, and what they do.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final global = ref.watch(adminGlobalProvider).value ?? const {};
    final daily = ref.watch(adminDailyProvider).value ?? const <DailyMetric>[];
    final users = ref.watch(adminUsersProvider);
    final text = Theme.of(context).textTheme;
    int g(String k) => (global[k] as num?)?.toInt() ?? 0;

    final today = daily.isEmpty ? null : daily.last;
    final mau = g('users');
    final dau = today?.get('activeUsers') ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Owner dashboard')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _Kpi('Total users', g('users'), Icons.people_alt_rounded, Brand.aurora),
              _Kpi('Active today', dau, Icons.bolt_rounded, Brand.ember),
              _Kpi('Subscribers', g('subscribers'), Icons.workspace_premium_rounded, Brand.iris),
              _Kpi('On trial', g('trials'), Icons.timer_rounded, Brand.bloom),
              _Kpi('App opens', g('app_open'), Icons.touch_app_rounded, Brand.success),
              _Kpi('Check-ins', g('form_submit'), Icons.edit_note_rounded, Brand.aurora),
              _Kpi('Pages read', g('pdf_page_view'), Icons.menu_book_rounded, Brand.iris),
              _Kpi('Audio plays', g('audio_play'), Icons.headphones_rounded, Brand.ember),
              _Kpi('AI narrations', g('ai_narration'), Icons.record_voice_over_rounded, Brand.bloom),
              _Kpi('Capture attempts', g('capture_attempt'), Icons.no_photography_rounded, Brand.danger),
            ],
          ),
          const SectionTitle('Daily active users · 30 days'),
          GlassCard(child: _DauChart(daily: daily)),
          const SectionTitle('Engagement mix · today'),
          GlassCard(
            child: CategoryBars(
              values: {
                for (final k in ['app_open', 'pdf_page_view', 'audio_play', 'form_submit', 'ai_narration', 'book_open'])
                  k.replaceAll('_', ' '): (today?.get(k) ?? 0).toDouble(),
              },
            ),
          ),
          if (mau > 0) ...[
            const SectionTitle('Stickiness'),
            GlassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  RingGauge(
                    progress: dau / mau,
                    caption: 'DAU / total',
                    center: Text('${(dau / mau * 100).toStringAsFixed(0)}%', style: text.headlineSmall),
                  ),
                  RingGauge(
                    progress: g('subscribers') / mau,
                    color: Brand.iris,
                    caption: 'paid conversion',
                    center: Text('${(g('subscribers') / mau * 100).toStringAsFixed(0)}%', style: text.headlineSmall),
                  ),
                ],
              ),
            ),
          ],
          SectionTitle('Users', trailing: Text(users.value?.length.toString() ?? '', style: text.labelLarge)),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name or phone'),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
          const SizedBox(height: 12),
          ...users.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [Text('$e')],
            data: (list) => [
              for (final u in list.where(
                (u) => _query.isEmpty || u.name.toLowerCase().contains(_query) || u.phone.contains(_query),
              ))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(u.name.characters.first.toUpperCase())),
                    title: Text(u.name),
                    subtitle: Text(
                      '${u.stat('app_open')} opens · ${u.stat('form_submit')} check-ins · '
                      '${u.lastActive == null ? 'never' : DateFormat('d MMM HH:mm').format(u.lastActive!)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/admin/user/${u.uid}'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const Spacer(),
        AnimatedCounter(value: value.toDouble(), style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _DauChart extends StatelessWidget {
  const _DauChart({required this.daily});
  final List<DailyMetric> daily;

  @override
  Widget build(BuildContext context) {
    final maxY = daily.fold<int>(1, (m, d) => math.max(m, d.get('activeUsers'))).toDouble() * 1.2;
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i % 7 != 0 || i >= daily.length) return const SizedBox.shrink();
                  return Text(DateFormat('d/M').format(daily[i].day), style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < daily.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: daily[i].get('activeUsers').toDouble(),
                    width: 6,
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Brand.iris, Brand.aurora],
                    ),
                  ),
                ],
              ),
          ],
        ),
        duration: Brand.motionSlow,
      ),
    );
  }
}
