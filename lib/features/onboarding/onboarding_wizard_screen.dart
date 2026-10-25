import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import 'onboarding_profile.dart';
import 'onboarding_repository.dart';

typedef _Update = void Function(OnboardingProfile Function(OnboardingProfile));

class _StepSpec {
  const _StepSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.accent,
    required this.visual,
    required this.input,
    this.valid,
  });

  final String id;
  final String Function(OnboardingProfile) title;
  final String description;
  final Color accent;
  final Widget Function(BuildContext, OnboardingProfile) visual;
  final Widget Function(BuildContext, OnboardingProfile, _Update) input;
  final bool Function(OnboardingProfile)? valid;
}

/// The identity-first onboarding wizard. Every screen follows the same
/// rhythm: live animated infographic → title → description → input.
/// Answers autosave as the user goes, and the final review lets them
/// correct anything before the AI agent builds their plan.
class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  ConsumerState<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends ConsumerState<OnboardingWizardScreen> {
  OnboardingProfile _p = const OnboardingProfile();
  int _step = 0;
  bool _loading = true;
  bool _forward = true;
  late final List<_StepSpec> _steps = _buildSteps();

  @override
  void initState() {
    super.initState();
    ref
        .read(onboardingRepositoryProvider)
        .load()
        .then((d) {
          if (!mounted) return;
          setState(() {
            _p = d.profile;
            _step = d.step.clamp(0, _steps.length - 1);
            _loading = false;
          });
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  void _update(OnboardingProfile Function(OnboardingProfile) f) {
    setState(() => _p = f(_p));
    ref.read(onboardingRepositoryProvider).autosave(_p, _step);
  }

  void _go(int step) {
    HapticFeedback.selectionClick();
    setState(() {
      _forward = step > _step;
      _step = step;
    });
    ref.read(onboardingRepositoryProvider).autosave(_p, _step);
    ref.read(analyticsProvider).log(AppEvent.onboardingStep, {'step': _steps[step].id});
  }

  Future<void> _finish() async {
    await ref.read(onboardingRepositoryProvider).complete(_p);
    ref.read(analyticsProvider).log(AppEvent.onboardingComplete, {'severity': _p.severity});
    if (mounted) context.go('/onboarding/plan');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final spec = _steps[_step];
    final last = _step == _steps.length - 1;
    final valid = spec.valid?.call(_p) ?? true;

    return Scaffold(
      body: AuroraBackground(
        accent: spec.accent,
        child: SafeArea(
          child: Column(
            children: [
              _ProgressHeader(
                step: _step,
                total: _steps.length,
                accent: spec.accent,
                onBack: _step == 0 ? null : () => _go(_step - 1),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Brand.motion,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(spec.id);
                    final dx = (incoming == _forward) ? 0.15 : -0.15;
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: ListView(
                    key: ValueKey(spec.id),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      ScreenHeader(
                        visual: GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: Center(child: spec.visual(context, _p)),
                          ),
                        ),
                        title: spec.title(_p),
                        description: spec.description,
                      ),
                      const SizedBox(height: 28),
                      spec.input(context, _p, _update).animate().fadeIn(delay: 300.ms, duration: Brand.motion),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: GradientButton(
                  label: last ? 'Build my plan' : 'Continue',
                  icon: last ? Icons.auto_awesome_rounded : Icons.arrow_forward_rounded,
                  gradient: Brand.gradientFor(Brand.accents.entries.firstWhere((e) => e.value == spec.accent).key),
                  onPressed: valid ? (last ? _finish : () => _go(_step + 1)) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_StepSpec> _buildSteps() => [
    _StepSpec(
      id: 'identity',
      title: (p) => p.displayName.isEmpty ? 'Welcome. Who are you?' : 'Welcome, ${p.displayName.split(' ').first}.',
      description: 'This is your private space. Let\'s start with your name and why you\'re here.',
      accent: Brand.aurora,
      valid: (p) => p.displayName.trim().length >= 2,
      visual: (_, p) => _AvatarOrb(name: p.displayName),
      input: (context, p, update) => Column(
        children: [
          TextFormField(
            initialValue: p.displayName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Your name'),
            onChanged: (v) => update((p) => p.copyWith(displayName: v)),
          ),
          const SizedBox(height: 16),
          _ChoiceCards(
            options: const {
              'individual': ('For myself', Icons.person_rounded),
              'counselor': ('I\'m a counselor / coach', Icons.health_and_safety_rounded),
              'supporter': ('Supporting someone', Icons.volunteer_activism_rounded),
            },
            selected: p.role,
            onSelected: (v) => update((p) => p.copyWith(role: v)),
          ),
        ],
      ),
    ),
    _StepSpec(
      id: 'identity_statement',
      title: (_) => 'Who are you becoming?',
      description: 'Lasting change starts with identity, not willpower. Choose — or write — yours.',
      accent: Brand.iris,
      valid: (p) => p.identity.trim().isNotEmpty,
      visual: (_, p) => Column(
        children: [
          const AnimatedStepIcon(
            icon: Icons.self_improvement_rounded,
            motion: StepIconMotion.breathe,
            color: Brand.iris,
          ),
          AnimatedSwitcher(
            duration: Brand.motion,
            child: Text(
              p.identity.isEmpty ? '“I am someone who…”' : '“${p.identity}”',
              key: ValueKey(p.identity),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
      input: (context, p, update) => Column(
        children: [
          for (final o in OnboardingProfile.identityOptions)
            _SelectTile(
              label: o,
              selected: p.identity == o,
              onTap: () => update((p) => p.copyWith(identity: o)),
            ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: OnboardingProfile.identityOptions.contains(p.identity) ? '' : p.identity,
            decoration: const InputDecoration(hintText: 'Or write your own…'),
            onChanged: (v) => update((p) => p.copyWith(identity: v)),
          ),
        ],
      ),
    ),
    _StepSpec(
      id: 'habits',
      title: (_) => 'What pulls you in?',
      description: 'Select everything that takes more of your time than you\'d like. No judgement here.',
      accent: Brand.ember,
      valid: (p) => p.habits.isNotEmpty,
      visual: (_, p) => CategoryBars(
        values: {for (var i = 0; i < p.habits.length; i++) p.habits[i]: (p.dailyHours / (i + 1)).clamp(0.4, 12)},
      ),
      input: (_, p, update) => _MultiChips(
        options: OnboardingProfile.habitOptions,
        selected: p.habits,
        onChanged: (v) => update((p) => p.copyWith(habits: v)),
      ),
    ),
    _StepSpec(
      id: 'screen_time',
      title: (_) => 'Your daily screen time',
      description: 'A rough estimate of non-essential screen time per day. Check your phone\'s usage stats if unsure.',
      accent: Brand.bloom,
      visual: (context, p) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          RingGauge(
            progress: p.dailyHours / 16,
            color: Brand.bloom,
            size: 120,
            caption: 'of waking hours',
            center: AnimatedCounter(
              value: p.dailyHours / 16 * 100,
              suffix: '%',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Column(
            children: [
              AnimatedCounter(value: p.hoursPerYear / 24, style: Theme.of(context).textTheme.displaySmall),
              Text('days per year', style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ],
      ),
      input: (context, p, update) => Column(
        children: [
          Text('${p.dailyHours.toStringAsFixed(1)} hours / day', style: Theme.of(context).textTheme.titleLarge),
          Slider(
            activeColor: Brand.bloom,
            value: p.dailyHours,
            min: 0.5,
            max: 14,
            divisions: 27,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              update((p) => p.copyWith(dailyHours: v));
            },
          ),
        ],
      ),
    ),
    _StepSpec(
      id: 'peak_times',
      title: (_) => 'When is it hardest?',
      description: 'Knowing your risk windows lets us time reminders and check-ins precisely.',
      accent: Brand.iris,
      valid: (p) => p.peakTimes.isNotEmpty,
      visual: (_, p) => _DayClock(active: p.peakTimes),
      input: (_, p, update) => _MultiChips(
        options: OnboardingProfile.peakOptions,
        selected: p.peakTimes,
        onChanged: (v) => update((p) => p.copyWith(peakTimes: v)),
      ),
    ),
    _StepSpec(
      id: 'triggers',
      title: (_) => 'What sets it off?',
      description: 'Urges usually follow a feeling. Name yours — awareness is the first interruption.',
      accent: Brand.ember,
      valid: (p) => p.triggers.isNotEmpty,
      visual: (_, p) => BubbleCloud(items: p.triggers),
      input: (_, p, update) => _MultiChips(
        options: OnboardingProfile.triggerOptions,
        selected: p.triggers,
        onChanged: (v) => update((p) => p.copyWith(triggers: v)),
      ),
    ),
    _StepSpec(
      id: 'goals',
      title: (_) => 'What will you do with the time?',
      description: 'Reclaimed attention needs somewhere to go. Pick what matters to you.',
      accent: Brand.success,
      valid: (p) => p.goals.isNotEmpty,
      visual: (context, p) => Column(
        children: [
          TrendChart(
            color: Brand.success,
            height: 110,
            points: [for (var w = 0; w <= 12; w++) w * (p.goals.length + 1) * p.dailyMinutesGoal / 60],
          ),
          Text('Projected hours reinvested over 12 weeks', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      input: (_, p, update) => _MultiChips(
        options: OnboardingProfile.goalOptions,
        selected: p.goals,
        onChanged: (v) => update((p) => p.copyWith(goals: v)),
      ),
    ),
    _StepSpec(
      id: 'coach_style',
      title: (_) => 'How should we guide you?',
      description: 'Your coach\'s voice — used in your plan and by the AI narrator when it reads to you.',
      accent: Brand.aurora,
      visual: (_, p) => AnimatedStepIcon(
        icon: switch (p.coachStyle) {
          'storyteller' => Icons.auto_stories_rounded,
          'motivator' => Icons.local_fire_department_rounded,
          _ => Icons.school_rounded,
        },
        motion: StepIconMotion.wave,
        color: switch (p.coachStyle) {
          'storyteller' => Brand.iris,
          'motivator' => Brand.ember,
          _ => Brand.aurora,
        },
      ),
      input: (_, p, update) => _ChoiceCards(
        options: const {
          'storyteller': ('Storyteller — warm, narrative', Icons.auto_stories_rounded),
          'teacher': ('Teacher — clear, structured', Icons.school_rounded),
          'motivator': ('Motivator — bold, energizing', Icons.local_fire_department_rounded),
        },
        selected: p.coachStyle,
        onSelected: (v) => update((p) => p.copyWith(coachStyle: v)),
      ),
    ),
    _StepSpec(
      id: 'commitment',
      title: (_) => 'Your daily commitment',
      description: 'How many minutes a day will you take back? Start small — consistency beats intensity.',
      accent: Brand.success,
      visual: (context, p) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          RingGauge(
            progress: p.dailyMinutesGoal / (p.dailyHours * 60),
            color: Brand.success,
            size: 120,
            caption: 'of current usage',
            center: AnimatedCounter(
              value: p.dailyMinutesGoal.toDouble(),
              suffix: 'm',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Column(
            children: [
              AnimatedCounter(value: p.dailyMinutesGoal * 90 / 60, style: Theme.of(context).textTheme.displaySmall),
              Text('hours back in 90 days', style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ],
      ),
      input: (context, p, update) => Slider(
        activeColor: Brand.success,
        value: p.dailyMinutesGoal.toDouble(),
        min: 10,
        max: math.max(30, math.min(240, p.dailyHours * 60)),
        divisions: 23,
        label: '${p.dailyMinutesGoal} min',
        onChanged: (v) => update((p) => p.copyWith(dailyMinutesGoal: v.round())),
      ),
    ),
    _StepSpec(
      id: 'review',
      title: (_) => 'Is this you?',
      description: 'Review and correct anything. Tap a row to edit it — your answers are saved.',
      accent: Brand.iris,
      visual: (context, p) => RingGauge(
        progress: p.severity / 100,
        color: switch (p.severityBand) {
          'high' => Brand.danger,
          'moderate' => Brand.ember,
          _ => Brand.success,
        },
        caption: 'Attention load · ${p.severityBand}',
        center: AnimatedCounter(value: p.severity.toDouble(), style: Theme.of(context).textTheme.displaySmall),
      ),
      input: (context, p, _) => Column(
        children: [
          _ReviewRow('Name', p.displayName, () => _go(0)),
          _ReviewRow('Identity', p.identity, () => _go(1)),
          _ReviewRow('Habits', p.habits.join(', '), () => _go(2)),
          _ReviewRow('Screen time', '${p.dailyHours.toStringAsFixed(1)} h/day', () => _go(3)),
          _ReviewRow('Hardest times', p.peakTimes.join(', '), () => _go(4)),
          _ReviewRow('Triggers', p.triggers.join(', '), () => _go(5)),
          _ReviewRow('Goals', p.goals.join(', '), () => _go(6)),
          _ReviewRow('Coach', p.coachStyle, () => _go(7)),
          _ReviewRow('Commitment', '${p.dailyMinutesGoal} min/day', () => _go(8)),
        ],
      ),
    ),
  ];
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.total, required this.accent, this.onBack});
  final int step;
  final int total;
  final Color accent;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
    child: Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: AnimatedOpacity(
            opacity: onBack == null ? 0 : 1,
            duration: Brand.motionFast,
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (step + 1) / total),
              duration: Brand.motion,
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: accent,
                backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text('${step + 1}/$total', style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _AvatarOrb extends StatelessWidget {
  const _AvatarOrb({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
    return Stack(
      alignment: Alignment.center,
      children: [
        const AnimatedStepIcon(icon: Icons.fingerprint_rounded, motion: StepIconMotion.orbit, size: 104),
        if (initials.isNotEmpty)
          Container(
            width: 104,
            height: 104,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Brand.auroraGradient),
            child: Text(initials, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
          ).animate(key: ValueKey(initials)).scale(duration: Brand.motionFast, curve: Curves.easeOutBack),
      ],
    );
  }
}

class _DayClock extends StatelessWidget {
  const _DayClock({required this.active});
  final List<String> active;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 150,
    child: TweenAnimationBuilder<double>(
      key: ValueKey(active.join()),
      tween: Tween(begin: 0, end: 1),
      duration: Brand.motion,
      builder: (context, t, _) =>
          CustomPaint(painter: _DayClockPainter(active, t, Theme.of(context).colorScheme.onSurface)),
    ),
  );
}

class _DayClockPainter extends CustomPainter {
  _DayClockPainter(this.active, this.t, this.ink);
  final List<String> active;
  final double t;
  final Color ink;

  static const _segments = {'Morning': (6, 11), 'Midday': (11, 16), 'Evening': (16, 22), 'Late night': (22, 30)};

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(12);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = ink.withValues(alpha: 0.07);
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    final colors = [Brand.ember, Brand.aurora, Brand.iris, Brand.bloom];
    var i = 0;
    for (final e in _segments.entries) {
      final start = (e.value.$1 / 24) * 2 * math.pi - math.pi / 2;
      final sweep = ((e.value.$2 - e.value.$1) / 24) * 2 * math.pi;
      final on = active.contains(e.key);
      canvas.drawArc(
        rect,
        start,
        sweep * (on ? t : 1) - 0.04,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 16 : 4
          ..strokeCap = StrokeCap.round
          ..color = on ? colors[i] : ink.withValues(alpha: 0.12),
      );
      i++;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '24h',
        style: TextStyle(color: ink.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, size.center(Offset(-tp.width / 2, -tp.height / 2)));
  }

  @override
  bool shouldRepaint(_DayClockPainter old) => true;
}

class _MultiChips extends StatelessWidget {
  const _MultiChips({required this.options, required this.selected, required this.onChanged});
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    alignment: WrapAlignment.center,
    children: [
      for (final (i, o) in options.indexed)
        FilterChip(
          label: Text(o),
          selected: selected.contains(o),
          showCheckmark: false,
          avatar: selected.contains(o) ? const Icon(Icons.check_circle_rounded, size: 18, color: Brand.aurora) : null,
          onSelected: (on) {
            HapticFeedback.lightImpact();
            onChanged(on ? [...selected, o] : selected.where((s) => s != o).toList());
          },
        ).animate().fadeIn(delay: (40 * i).ms).scale(begin: const Offset(0.9, 0.9)),
    ],
  );
}

class _ChoiceCards extends StatelessWidget {
  const _ChoiceCards({required this.options, required this.selected, required this.onSelected});
  final Map<String, (String, IconData)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final e in options.entries)
        _SelectTile(label: e.value.$1, icon: e.value.$2, selected: selected == e.key, onTap: () => onSelected(e.key)),
    ],
  );
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: Brand.motionFast,
        decoration: BoxDecoration(
          color: selected ? Brand.aurora.withValues(alpha: 0.12) : scheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(color: selected ? Brand.aurora : scheme.onSurface.withValues(alpha: 0.08), width: 1.4),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
          leading: icon == null ? null : Icon(icon, color: selected ? Brand.aurora : null),
          title: Text(label),
          trailing: AnimatedScale(
            scale: selected ? 1 : 0,
            duration: Brand.motionFast,
            curve: Curves.easeOutBack,
            child: const Icon(Icons.check_circle_rounded, color: Brand.aurora),
          ),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value, this.onEdit);
  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(value.isEmpty ? '—' : value, style: Theme.of(context).textTheme.bodyLarge),
    trailing: const Icon(Icons.edit_rounded, size: 18),
    onTap: onEdit,
  );
}
