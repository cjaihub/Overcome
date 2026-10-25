import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/brand.dart';

/// Frosted, softly bordered surface used for all cards.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.gradient});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: gradient,
                color: gradient == null ? scheme.surface.withValues(alpha: 0.62) : null,
                borderRadius: BorderRadius.circular(Brand.radiusLg),
                border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uniform screen header: live infographic on top, then title,
/// description — the input goes beneath it.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.visual, required this.title, required this.description});

  final Widget visual;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: visual).animate().fadeIn(duration: Brand.motion).scale(begin: const Offset(0.92, 0.92)),
        const SizedBox(height: 20),
        Text(
          title,
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 120.ms, duration: Brand.motion).slideY(begin: 0.25, curve: Curves.easeOutCubic),
        const SizedBox(height: 8),
        Text(
          description,
          style: text.bodyLarge?.copyWith(color: text.bodyLarge?.color?.withValues(alpha: 0.7)),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 220.ms, duration: Brand.motion).slideY(begin: 0.25, curve: Curves.easeOutCubic),
      ],
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.gradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fill = gradient ?? Brand.auroraGradient;
    final glow = fill is LinearGradient ? fill.colors.first : Brand.aurora;
    return AnimatedOpacity(
      duration: Brand.motionFast,
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: fill,
          borderRadius: BorderRadius.circular(Brand.radius),
          boxShadow: enabled
              ? [BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))]
              : null,
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
          onPressed: enabled ? onPressed : null,
          child: loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Brand.ink),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20)],
                  ],
                ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
        ?trailing,
      ],
    ),
  );
}

Future<void> showError(BuildContext context, Object error) async {
  final message = error.toString().replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Brand.danger));
}
