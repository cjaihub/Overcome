import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/services/firebase_providers.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import '../onboarding/onboarding_profile.dart';
import '../progress/progress_math.dart';
import '../progress/progress_repository.dart';
import '../progress/recovery_plan.dart';
import '../subscription/entitlement.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(userDocProvider).value ?? const {};
    final profile = OnboardingProfile.fromMap(doc['profile'] as Map<String, dynamic>?);
    final plan = ref.watch(planProvider).value;
    final checkIns = ref.watch(checkInsProvider).value ?? const <CheckIn>[];
    final ent = ref.watch(entitlementProvider);
    final text = Theme.of(context).textTheme;

    final streak = ProgressMath.streak(checkIns);
    final weekCount = ProgressMath.countSince(checkIns, const Duration(days: 7));
    final mood = ProgressMath.dailyMood(checkIns, days: 7);
    final started = (doc['onboardingCompletedAt'] as Timestamp?)?.toDate();
    final phaseIdx = plan == null ? 0 : ProgressMath.phaseIndex(started, [for (final p in plan.phases) p.weeks]);
    final phase = plan == null || plan.phases.isEmpty ? null : plan.phases[phaseIdx];
    final daysIn = started == null ? 0 : DateTime.now().difference(started).inDays + 1;
    final reclaimedHours = daysIn * profile.dailyMinutesGoal / 60;

    return AuroraBackground(
      accent: plan?.color ?? Brand.aurora,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting()},',
                      style: text.titleMedium?.copyWith(color: text.titleMedium?.color?.withValues(alpha: 0.6)),
                    ),
                    Text(
                      profile.displayName.isEmpty ? 'friend' : profile.displayName.split(' ').first,
                      style: text.headlineMedium,
                    ),
                  ],
                ),
              ),
              if (ent.inTrial)
                ActionChip(
                  avatar: const Icon(Icons.timer_rounded, size: 16),
                  label: Text('${ent.trialDaysLeft}d trial'),
                  onPressed: () => context.push('/paywall'),
                ),
            ],
          ),
          if (profile.identity.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${profile.identity}”', style: text.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 20),
          GlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                RingGauge(
                  progress: streak / 30,
                  size: 110,
                  color: Brand.ember,
                  caption: 'day streak',
                  center: AnimatedCounter(value: streak.toDouble(), style: text.headlineMedium),
                ),
                RingGauge(
                  progress: weekCount / 7,
                  size: 110,
                  caption: 'check-ins / week',
                  center: AnimatedCounter(value: weekCount.toDouble(), style: text.headlineMedium),
                ),
                RingGauge(
                  progress: (reclaimedHours / 100).clamp(0, 1),
                  size: 110,
                  color: Brand.success,
                  caption: 'hours reclaimed',
                  center: AnimatedCounter(value: reclaimedHours, style: text.headlineSmall),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1),
          if (plan != null) ...[
            SectionTitle('Today\'s check-ins', trailing: Text('${plan.forms.length}', style: text.labelLarge)),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: plan.forms.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) =>
                    _FormCard(form: plan.forms[i]).animate().fadeIn(delay: (80 * i).ms).slideX(begin: 0.2),
              ),
            ),
          ],
          if (phase != null) ...[
            SectionTitle('Phase ${phaseIdx + 1} · ${phase.title}'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedStepIcon(icon: plan!.iconData, color: plan.color, size: 44, motion: StepIconMotion.orbit),
                      const SizedBox(width: 8),
                      Expanded(child: Text(phase.focus, style: text.bodyLarge)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final a in phase.actions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 18, color: plan.color),
                          const SizedBox(width: 10),
                          Expanded(child: Text(a)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SectionTitle('Your week'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wellbeing score', style: text.labelLarge),
                const SizedBox(height: 12),
                TrendChart(
                  points: mood,
                  labels: [
                    for (var i = mood.length - 1; i >= 0; i--)
                      DateFormat.E().format(DateTime.now().subtract(Duration(days: i))).substring(0, 1),
                  ],
                ),
              ],
            ),
          ),
          if (plan != null && plan.affirmations.isNotEmpty) ...[
            const SizedBox(height: 16),
            GlassCard(
              gradient: Brand.gradientFor(plan.accent),
              child: Row(
                children: [
                  const Icon(Icons.format_quote_rounded, color: Brand.ink, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      plan.affirmations[DateTime.now().day % plan.affirmations.length],
                      style: text.titleMedium?.copyWith(color: Brand.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SectionTitle('Continue learning'),
          GlassCard(
            onTap: () => context.go('/library'),
            child: Row(
              children: [
                const AnimatedStepIcon(
                  icon: Icons.menu_book_rounded,
                  color: Brand.iris,
                  size: 44,
                  motion: StepIconMotion.wave,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Explore the library', style: text.titleMedium)),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.form});
  final FormTemplate form;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: GlassCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [form.color.withValues(alpha: 0.28), form.color.withValues(alpha: 0.06)],
      ),
      onTap: () => context.push('/form/${form.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(form.iconData, color: form.color),
          const Spacer(),
          Text(form.title, style: Theme.of(context).textTheme.titleSmall, maxLines: 2),
          Text(switch (form.frequency) {
            'weekly' => 'Weekly',
            'on_urge' => 'When an urge hits',
            _ => 'Daily',
          }, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}
