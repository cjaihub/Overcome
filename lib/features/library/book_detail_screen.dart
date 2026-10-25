import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../subscription/entitlement.dart';
import 'book.dart';
import 'book_3d.dart';
import 'library_repository.dart';

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).log(AppEvent.bookView, {'bookId': widget.bookId});
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bookProvider(widget.bookId)).value;
    final ent = ref.watch(entitlementProvider);
    if (book == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final unlocked = ent.canAccess(book.id);
    final text = Theme.of(context).textTheme;

    void open(String route) => unlocked ? context.push(route) : context.push('/paywall?book=${book.id}');

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(),
      body: AuroraBackground(
        accent: book.color,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 460,
              child: SafeArea(
                child: Center(
                  child: Hero(
                    tag: 'book-${book.id}',
                    child: InteractiveBook3D(book: book),
                  ),
                ),
              ),
            ),
            Text('Drag to rotate', style: text.labelSmall, textAlign: TextAlign.center).animate().fadeIn(delay: 600.ms),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(book.title, style: text.headlineMedium),
                  const SizedBox(height: 4),
                  Text(book.author, style: text.titleMedium?.copyWith(color: book.color)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(Icons.category_rounded, book.category),
                      if (book.pages > 0) _Pill(Icons.description_rounded, '${book.pages} pages'),
                      if (book.hasAudio)
                        _Pill(Icons.headphones_rounded, '${book.audioMinutes ~/ 60}h ${book.audioMinutes % 60}m'),
                      if (book.rating > 0) _Pill(Icons.star_rounded, book.rating.toStringAsFixed(1)),
                      const _Pill(Icons.shield_rounded, 'Protected'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(book.description, style: text.bodyLarge),
                  const SizedBox(height: 28),
                  if (!unlocked) ...[
                    GradientButton(
                      label: ent.hasPremium ? 'Buy this book' : 'Unlock with Premium',
                      icon: Icons.lock_open_rounded,
                      gradient: Brand.gradientFor(book.accent),
                      onPressed: () => context.push('/paywall?book=${book.id}'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (book.hasPdf)
                    _ActionTile(
                      icon: Icons.chrome_reader_mode_rounded,
                      title: 'Read',
                      subtitle: 'Secure in-app reader',
                      locked: !unlocked,
                      onTap: () => open('/book/${book.id}/read'),
                    ),
                  if (book.hasAudio)
                    _ActionTile(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Listen & read along',
                      subtitle: 'Narrated audio with live line highlighting',
                      locked: !unlocked,
                      onTap: () => open('/book/${book.id}/listen'),
                    ),
                  _ActionTile(
                    icon: Icons.record_voice_over_rounded,
                    title: 'AI narrator',
                    subtitle: 'Storyteller, teacher or motivator — your choice',
                    locked: !unlocked,
                    badge: 'AI',
                    onTap: () => open('/book/${book.id}/narrator'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 16), label: Text(label), visualDensity: VisualDensity.compact);
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool locked;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(gradient: Brand.auroraGradient, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Brand.iris, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          badge!,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(locked ? Icons.lock_rounded : Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

/// Shared helper for protected screens: resolves access once and maps the
/// not-entitled case to the paywall.
Future<BookAccess?> resolveAccess(BuildContext context, WidgetRef ref, String bookId) async {
  try {
    return await ref.read(libraryRepositoryProvider).access(bookId);
  } on NotEntitledException {
    if (context.mounted) context.pushReplacement('/paywall?book=$bookId');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
  return null;
}
