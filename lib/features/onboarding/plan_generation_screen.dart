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
import 'onboarding_repository.dart';

/// Shows the AI agent working live: it first looks for an existing,
/// clinically reviewed template that fits the user's profile, and only
/// generates a new on-brand plan when none matches.
class PlanGenerationScreen extends ConsumerStatefulWidget {
  const PlanGenerationScreen({super.key});

  @override
  ConsumerState<PlanGenerationScreen> createState() => _PlanGenerationScreenState();
}

class _PlanGenerationScreenState extends ConsumerState<PlanGenerationScreen> {
  String? _runId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final id = await ref.read(onboardingRepositoryProvider).startPlanAgent();
      if (mounted) setState(() => _runId = id);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _runId;
    return Scaffold(
      body: AuroraBackground(
        accent: Brand.iris,
        child: SafeArea(
          child: id == null
              ? _error == null
                    ? const Center(child: CircularProgressIndicator())
                    : _ErrorView(onRetry: _start)
              : StreamBuilder<Map<String, dynamic>?>(
                  stream: ref.read(onboardingRepositoryProvider).watchRun(id),
                  builder: (context, snap) => _RunView(run: snap.data ?? const {}, onRetry: _start),
                ),
        ),
      ),
    );
  }
}

class _RunView extends ConsumerWidget {
  const _RunView({required this.run, required this.onRetry});
  final Map<String, dynamic> run;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = run['status'] as String? ?? 'queued';
    final steps = [for (final s in (run['steps'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    final done = status == 'done';
    final source = run['source'] as String?;
    final text = Theme.of(context).textTheme;

    if (status == 'error') return _ErrorView(onRetry: onRetry, message: run['error'] as String?);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        ScreenHeader(
          key: ValueKey(done),
          visual: AnimatedStepIcon(
            icon: done ? Icons.check_rounded : Icons.auto_awesome_rounded,
            motion: done ? StepIconMotion.rise : StepIconMotion.orbit,
            color: done ? Brand.success : Brand.iris,
            size: 110,
          ),
          title: done ? (run['planTitle'] as String? ?? 'Your plan is ready') : 'Designing your plan',
          description: done
              ? (source == 'template'
                    ? 'Matched to a proven program and personalised for you.'
                    : 'Created just for you, from scratch.')
              : 'Your AI coach is analysing your answers in real time.',
        ),
        const SizedBox(height: 32),
        GlassCard(
          child: Column(
            children: [
              for (final (i, s) in steps.indexed)
                _AgentStep(
                  label: s['label'] as String? ?? '',
                  detail: s['detail'] as String?,
                  state: s['state'] as String? ?? 'running',
                ).animate().fadeIn(delay: (60 * i).ms).slideX(begin: 0.1),
              if (steps.isEmpty) const _AgentStep(label: 'Connecting to your coach…', state: 'running'),
            ],
          ),
        ),
        const SizedBox(height: 32),
        if (done)
          GradientButton(
            label: 'Start my journey',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {
              HapticFeedback.heavyImpact();
              ref.read(analyticsProvider).log(AppEvent.planAssigned, {'source': source});
              context.go('/home');
            },
          ).animate().fadeIn().slideY(begin: 0.3),
        if (!done) Text('This usually takes under a minute.', style: text.labelMedium, textAlign: TextAlign.center),
      ],
    );
  }
}

class _AgentStep extends StatelessWidget {
  const _AgentStep({required this.label, required this.state, this.detail});
  final String label;
  final String state;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final running = state == 'running';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 24,
            child: AnimatedSwitcher(
              duration: Brand.motionFast,
              child: running
                  ? const CircularProgressIndicator(strokeWidth: 2.2, color: Brand.iris)
                  : Icon(
                      state == 'skipped' ? Icons.remove_circle_outline_rounded : Icons.check_circle_rounded,
                      color: state == 'skipped' ? Colors.grey : Brand.success,
                      key: ValueKey(state),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                if (detail != null)
                  Text(detail!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry, this.message});
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScreenHeader(
          visual: const AnimatedStepIcon(icon: Icons.cloud_off_rounded, color: Brand.danger),
          title: 'We hit a snag',
          description: message ?? 'Your answers are saved. Let\'s try that again.',
        ),
        const SizedBox(height: 24),
        GradientButton(label: 'Retry', onPressed: onRetry),
      ],
    ),
  );
}
