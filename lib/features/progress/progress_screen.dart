import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/services/firebase_providers.dart';
import '../../core/services/usage_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import '../onboarding/onboarding_profile.dart';
import '../tracker/guardian_controller.dart';
import '../tracker/usage_insights.dart';
import 'progress_math.dart';
import 'progress_repository.dart';

/// The live tracker: real device usage (refreshing every 15 s), weekly
/// trends against the user's target, and recovery check-ins.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(child: Text('Progress', style: text.headlineMedium)),
                const _LiveDot(),
              ],
            ),
          ),
          const TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: 'Live'),
              Tab(text: 'Week'),
              Tab(text: 'Recovery'),
            ],
          ),
          const Expanded(child: TabBarView(children: [_LiveTab(), _WeekTab(), _RecoveryTab()])),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(color: Brand.success, shape: BoxShape.circle),
      ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.3, duration: 900.ms),
      const SizedBox(width: 6),
      Text('LIVE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Brand.success)),
    ],
  );
}

// ---------------------------------------------------------------- Live tab

class _LiveTab extends ConsumerWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(usageStatusProvider).value;
    if (status == null) return const Center(child: CircularProgressIndicator());
    if (!status.supported) return const _UnsupportedNotice();
    if (!status.usageAccess) return _PermissionSetup(status: status);

    final usage = ref.watch(liveUsageProvider).value;
    final profile = OnboardingProfile.fromMap(ref.watch(userDocProvider).value?['profile'] as Map<String, dynamic>?);
    final guardian = ref.watch(guardianProvider);
    final checkIns = ref.watch(checkInsProvider).value ?? const <CheckIn>[];
    if (usage == null) return const Center(child: CircularProgressIndicator());

    final target = UsageInsights.targetMinutes(
      baselineHours: profile.dailyHours,
      commitMinutes: profile.dailyMinutesGoal,
    );
    final checkedIn = checkIns.any((c) => DateUtils.isSameDay(c.at, DateTime.now()));
    final score = UsageInsights.focusScore(usage, targetMinutes: target, checkedIn: checkedIn);
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(liveUsageProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const _CurrentSessionPill(),
          const SizedBox(height: 12),
          GlassCard(
            child: Row(
              children: [
                RingGauge(
                  progress: usage.total.inMinutes / target,
                  size: 138,
                  color: usage.total.inMinutes > target ? Brand.ember : Brand.aurora,
                  caption: 'of ${UsageInsights.format(Duration(minutes: target))} target',
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedCounter(value: usage.total.inMinutes.toDouble(), suffix: 'm', style: text.headlineMedium),
                      Text('today', style: text.labelSmall),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MiniStat(Icons.lock_open_rounded, 'Pickups', usage.pickups.toDouble(), Brand.iris),
                      _MiniStat(
                        Icons.notifications_active_rounded,
                        'Notifications',
                        usage.notifications.toDouble(),
                        Brand.bloom,
                        hint: status.notificationAccess ? null : 'Enable',
                        onHint: () => ref.read(usageServiceProvider).openNotificationAccessSettings(),
                      ),
                      _MiniStat(
                        Icons.nightlight_round,
                        'After 23:00',
                        usage.lateNightMinutes,
                        Brand.ember,
                        suffix: 'm',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.06),
          const SizedBox(height: 12),
          _FocusScoreCard(score: score),
          const SectionTitle('Hour by hour'),
          GlassCard(child: _HourlyChart(usage: usage)),
          const SectionTitle('Insights'),
          for (final (i, line) in UsageInsights.insights(
            usage,
            targetMinutes: target,
            tracked: guardian.tracked,
          ).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Brand.aurora, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(line)),
                  ],
                ),
              ).animate().fadeIn(delay: (80 * i).ms).slideX(begin: 0.06),
            ),
          SectionTitle('Apps today', trailing: Text('Tap to watch with Guardian', style: text.labelSmall)),
          for (final a in usage.apps.take(12))
            _AppRow(
              app: a,
              maxMinutes: math.max(1, usage.apps.first.foreground.inMinutes),
              tracked: guardian.tracked.contains(a.package),
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(guardianProvider.notifier).toggleTracked(a.package, userName: profile.displayName);
              },
            ),
          const SizedBox(height: 12),
          const _GuardianCard(),
        ],
      ),
    );
  }
}

class _CurrentSessionPill extends ConsumerStatefulWidget {
  const _CurrentSessionPill();

  @override
  ConsumerState<_CurrentSessionPill> createState() => _CurrentSessionPillState();
}

class _CurrentSessionPillState extends ConsumerState<_CurrentSessionPill> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(currentSessionProvider).value;
    final tracked = ref.watch(guardianProvider).tracked;
    final elapsed = s == null ? Duration.zero : DateTime.now().difference(s.since);
    final watched = s != null && tracked.contains(s.package);
    final label = s == null
        ? 'You\'re here, in Ovacome. Good place to be.'
        : '${s.label} · ${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return AnimatedContainer(
      duration: Brand.motion,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (watched ? Brand.ember : Brand.iris).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: (watched ? Brand.ember : Brand.iris).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(watched ? Icons.visibility_rounded : Icons.phone_android_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          if (watched) Text('watched', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Brand.ember)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.icon, this.label, this.value, this.color, {this.suffix = '', this.hint, this.onHint});
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  final String suffix;
  final String? hint;
  final VoidCallback? onHint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        if (hint != null)
          TextButton(onPressed: onHint, child: Text(hint!))
        else
          AnimatedCounter(value: value, suffix: suffix, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _FocusScoreCard extends StatelessWidget {
  const _FocusScoreCard({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75 ? Brand.success : (score >= 50 ? Brand.aurora : Brand.ember);
    final label = score >= 75 ? 'Protected' : (score >= 50 ? 'Steady' : 'Drifting');
    return GlassCard(
      gradient: LinearGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.04)]),
      child: Row(
        children: [
          AnimatedStepIcon(
            icon: Icons.center_focus_strong_rounded,
            color: color,
            size: 48,
            motion: StepIconMotion.breathe,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Focus score · $label', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'Screen time vs target, unlocks, late nights and notifications.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          AnimatedCounter(
            value: score.toDouble(),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.usage});
  final UsageSummary usage;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().hour;
    final maxY = math.max(10.0, usage.hourly.reduce(math.max) * 1.2);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 170,
      child: BarChart(
        duration: Brand.motionSlow,
        BarChartData(
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                '${g.x}:00\n${rod.toY.round()} min · ${usage.hourlyNotifications[g.x]} notif.',
                const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, _) => v.toInt() % 6 == 0
                    ? Text('${v.toInt()}h', style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5)))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          barGroups: [
            for (var h = 0; h < 24; h++)
              BarChartGroupData(
                x: h,
                barRods: [
                  BarChartRodData(
                    toY: usage.hourly[h],
                    width: 7,
                    borderRadius: BorderRadius.circular(3),
                    color: h > now
                        ? onSurface.withValues(alpha: 0.06)
                        : UsageSummary.lateNightHours.contains(h)
                        ? Brand.ember
                        : (h == now ? Brand.aurora : Brand.iris),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.maxMinutes, required this.tracked, required this.onTap});
  final AppUsage app;
  final int maxMinutes;
  final bool tracked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: app.icon == null
                  ? const SizedBox.square(dimension: 40, child: Icon(Icons.apps_rounded))
                  : Image.memory(app.icon!, width: 40, height: 40, gaplessPlayback: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(app.label, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                      ),
                      Text(UsageInsights.format(app.foreground), style: text.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: app.foreground.inMinutes / maxMinutes),
                    duration: Brand.motionSlow,
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                      color: tracked ? Brand.ember : Brand.iris,
                      backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${app.launches} opens · ${app.notifications} notifications', style: text.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              tracked ? Icons.visibility_rounded : Icons.visibility_outlined,
              color: tracked ? Brand.ember : null,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardianCard extends ConsumerWidget {
  const _GuardianCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(guardianProvider);
    final name = (ref.watch(userDocProvider).value?['profile'] as Map?)?['displayName'] as String? ?? '';
    return GlassCard(
      gradient: Brand.tealGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_moon_rounded, color: Brand.aurora),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Guardian mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
              Switch(
                value: g.enabled,
                onChanged: (on) =>
                    ref.read(guardianProvider.notifier).update((s) => s.copyWith(enabled: on), userName: name),
              ),
            ],
          ),
          Text(
            g.enabled
                ? 'Watching ${g.tracked.length} app${g.tracked.length == 1 ? '' : 's'} in real time — nudges after ${g.sessionLimitMin} min sessions, at ${g.dailyLimitMin} min a day, and late at night${g.voiceNudges ? ', spoken aloud' : ''}.'
                : 'Turn on to get real-time reminders based on how you use your phone, even when Ovacome is closed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _PermissionSetup extends ConsumerWidget {
  const _PermissionSetup({required this.status});
  final UsageStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const ScreenHeader(
        visual: AnimatedStepIcon(icon: Icons.insights_rounded, motion: StepIconMotion.orbit, color: Brand.iris),
        title: 'See your real screen time',
        description:
            'Allow Usage access so Ovacome can measure screen time, pickups and late-night use on this phone. '
            'Data stays yours — only daily totals are synced to your account.',
      ),
      const SizedBox(height: 28),
      GradientButton(
        label: 'Allow usage access',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => ref.read(usageServiceProvider).openUsageAccessSettings(),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => ref.invalidate(usageStatusProvider),
        child: const Text('I\'ve allowed it — refresh'),
      ),
    ],
  );
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(
      child: ScreenHeader(
        visual: AnimatedStepIcon(icon: Icons.phone_iphone_rounded, motion: StepIconMotion.pulse, color: Brand.iris),
        title: 'Screen Time stays with Apple',
        description:
            'iOS doesn\'t share app usage with third-party apps. Your check-ins, urges and reading progress are '
            'tracked in the Recovery tab, and the coach uses them to guide you.',
      ),
    ),
  );
}

// ---------------------------------------------------------------- Week tab

class _WeekTab extends ConsumerWidget {
  const _WeekTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(usageStatusProvider).value;
    if (status != null && (!status.supported || !status.usageAccess)) {
      return status.supported ? _PermissionSetup(status: status) : const _UnsupportedNotice();
    }
    final week = ref.watch(weekUsageProvider);
    final profile = OnboardingProfile.fromMap(ref.watch(userDocProvider).value?['profile'] as Map<String, dynamic>?);
    final target = UsageInsights.targetMinutes(
      baselineHours: profile.dailyHours,
      commitMinutes: profile.dailyMinutesGoal,
    );
    final text = Theme.of(context).textTheme;

    return week.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (days) {
        if (days.isEmpty) return const SizedBox.shrink();
        final reclaimed = UsageInsights.reclaimedMinutes(days, profile.dailyHours);
        final avg = days.fold(0, (s, d) => s + d.total.inMinutes) / days.length;
        final onTarget = days.where((d) => d.total.inMinutes <= target).length;
        final appTotals = <String, (String, int)>{};
        for (final d in days) {
          for (final a in d.apps) {
            final prev = appTotals[a.package];
            appTotals[a.package] = (a.label, (prev?.$2 ?? 0) + a.foreground.inMinutes);
          }
        }
        final topApps = appTotals.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                _Kpi('Daily avg', avg, 'm', Brand.iris),
                _Kpi('Days on target', onTarget.toDouble(), '/${days.length}', Brand.success),
                _Kpi('Hours reclaimed', reclaimed / 60, 'h', Brand.aurora, decimals: 1),
              ],
            ),
            const SectionTitle('Screen time vs target'),
            GlassCard(
              child: _WeekChart(days: days, target: target),
            ),
            const SectionTitle('Unlocks per day'),
            GlassCard(
              child: TrendChart(
                points: [for (final d in days) d.pickups.toDouble()],
                color: Brand.bloom,
                labels: [for (final d in days) DateFormat.E().format(d.day).substring(0, 1)],
              ),
            ),
            const SectionTitle('Where the week went'),
            GlassCard(child: CategoryBars(values: {for (final a in topApps.take(6)) a.$1: a.$2.toDouble()})),
            const SizedBox(height: 8),
            Text('Bars show total minutes across the last 8 days.', style: text.labelSmall),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.suffix, this.color, {this.decimals = 0});
  final String label;
  final double value;
  final String suffix;
  final Color color;
  final int decimals;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedCounter(
          value: value,
          suffix: suffix,
          decimals: decimals,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.target});
  final List<UsageSummary> days;
  final int target;

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(target * 1.4, days.map((d) => d.total.inMinutes).reduce(math.max) * 1.15).toDouble();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 190,
      child: BarChart(
        duration: Brand.motionSlow,
        BarChartData(
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: target.toDouble(),
                color: Brand.success,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  labelResolver: (_) => 'target',
                  style: const TextStyle(color: Brand.success, fontSize: 10),
                ),
              ),
            ],
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, _) => Text(
                  DateFormat.E().format(days[v.toInt()].day).substring(0, 2),
                  style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: days[i].total.inMinutes.toDouble(),
                    width: 18,
                    borderRadius: BorderRadius.circular(6),
                    color: days[i].total.inMinutes <= target ? Brand.iris : Brand.ember,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Recovery tab

class _RecoveryTab extends ConsumerWidget {
  const _RecoveryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkIns = ref.watch(checkInsProvider).value ?? const <CheckIn>[];
    final stats = (ref.watch(userDocProvider).value?['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final text = Theme.of(context).textTheme;
    final mood30 = ProgressMath.dailyMood(checkIns, days: 30);
    final urges = ProgressMath.countSince(checkIns, const Duration(days: 30), formId: 'urge_log');

    int stat(String k) => (stats[k] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
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
            _Stat('Nudges received', stat('nudge_sent').toDouble(), Icons.shield_moon_rounded, Brand.success),
            _Stat('Coach chats', stat('coach_message').toDouble(), Icons.forum_rounded, Brand.aurora),
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
