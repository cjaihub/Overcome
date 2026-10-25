import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/brand.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../subscription/entitlement.dart';
import 'book.dart';
import 'book_3d.dart';
import 'library_repository.dart';

/// Storefront: a 3D carousel of featured books, then the full catalogue.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _carousel = PageController(viewportFraction: 0.62);
  double _page = 0;
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _carousel.addListener(() => setState(() => _page = _carousel.page ?? 0));
  }

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider);
    final ent = ref.watch(entitlementProvider);
    return books.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final featured = all.where((b) => b.featured).toList();
        final categories = [
          'All',
          ...{for (final b in all) b.category},
        ];
        final shown = _category == 'All' ? all : all.where((b) => b.category == _category).toList();
        final focus = featured.isEmpty ? null : featured[_page.round().clamp(0, featured.length - 1)];

        return AuroraBackground(
          accent: focus?.color ?? Brand.iris,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                title: const Text('Library'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Chip(
                      avatar: Icon(ent.hasPremium ? Icons.workspace_premium_rounded : Icons.lock_rounded, size: 16),
                      label: Text(ent.label),
                    ),
                  ),
                ],
              ),
              if (featured.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 400,
                    child: PageView.builder(
                      controller: _carousel,
                      itemCount: featured.length,
                      itemBuilder: (context, i) {
                        final delta = i - _page;
                        final book = featured[i];
                        return GestureDetector(
                          onTap: () => context.push('/book/${book.id}'),
                          child: Transform.translate(
                            offset: Offset(0, delta.abs() * 30),
                            child: Transform.scale(
                              scale: 1 - delta.abs().clamp(0, 1) * 0.18,
                              child: Center(
                                child: Hero(
                                  tag: 'book-${book.id}',
                                  child: Book3D(book: book, width: 190, angle: -0.35 - delta * 0.9, tilt: 0.06),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (focus != null)
                SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: Brand.motion,
                    child: Column(
                      key: ValueKey(focus.id),
                      children: [
                        Text(
                          focus.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(focus.author, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: focus.color)),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    children: [
                      for (final c in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _BookTile(
                    book: shown[i],
                    locked: !ent.canAccess(shown[i].id),
                  ).animate().fadeIn(delay: (50 * math.min(i, 10)).ms).slideY(begin: 0.15),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.locked});
  final Book book;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/book/${book.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) => Book3D(book: book, width: c.maxWidth * 0.66, angle: -0.4, tilt: 0.05),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(book.title, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(book.author, style: text.bodySmall, maxLines: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              if (book.hasPdf) const Icon(Icons.menu_book_rounded, size: 14),
              if (book.hasAudio) ...[const SizedBox(width: 6), const Icon(Icons.headphones_rounded, size: 14)],
              const Spacer(),
              Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 14,
                color: locked ? null : Brand.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
