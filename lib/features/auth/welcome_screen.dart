import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _page = PageController();
  int _index = 0;

  static const _slides = [
    (
      Icons.self_improvement_rounded,
      StepIconMotion.breathe,
      Brand.aurora,
      'Discover yourself',
      'Understand what pulls your attention away — and who you are without it.',
    ),
    (
      Icons.track_changes_rounded,
      StepIconMotion.orbit,
      Brand.iris,
      'A plan that adapts',
      'An AI-guided recovery plan, built around your habits, triggers and goals.',
    ),
    (
      Icons.menu_book_rounded,
      StepIconMotion.wave,
      Brand.ember,
      'Learn & listen',
      'A private library of books and immersive audiobooks — read to you, your way.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_index];
    return Scaffold(
      body: AuroraBackground(
        accent: slide.$3,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    Image.asset(BrandAssets.horizontal(Theme.of(context).brightness), height: 34),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push('/sign-in?next=/redeem'),
                      child: const Text('I have a code'),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final s = _slides[i];
                      return Center(
                        child: ScreenHeader(
                          visual: AnimatedStepIcon(icon: s.$1, motion: s.$2, color: s.$3, size: 120),
                          title: s.$4,
                          description: s.$5,
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: Brand.motion,
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? slide.$3
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                GradientButton(
                  label: 'Continue with phone',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => context.push('/sign-in'),
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.4),
                const SizedBox(height: 12),
                Text('7 days free · then choose a plan', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
