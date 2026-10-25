import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/brand.dart';
import '../widgets/animated_step_icon.dart';
import '../widgets/aurora_background.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AuroraBackground(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimatedStepIcon(icon: Icons.all_inclusive_rounded, motion: StepIconMotion.pulse, size: 110),
            const SizedBox(height: 16),
            Text(
              Brand.name,
              style: Theme.of(context).textTheme.displaySmall,
            ).animate().fadeIn(duration: Brand.motion).slideY(begin: 0.3),
            const SizedBox(height: 6),
            Text(Brand.tagline, style: Theme.of(context).textTheme.bodyMedium).animate().fadeIn(delay: 300.ms),
          ],
        ),
      ),
    ),
  );
}
