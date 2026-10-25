import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/brand.dart';
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
            Image.asset(BrandAssets.stacked(Theme.of(context).brightness), width: 220)
                .animate()
                .fadeIn(duration: Brand.motion)
                .scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack)
                .then()
                .shimmer(duration: 1400.ms, color: Brand.aurora.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(Brand.tagline, style: Theme.of(context).textTheme.bodyMedium).animate().fadeIn(delay: 300.ms),
          ],
        ),
      ),
    ),
  );
}
