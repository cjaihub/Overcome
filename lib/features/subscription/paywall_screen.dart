import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../library/library_repository.dart';
import 'entitlement.dart';
import 'subscription_repository.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.bookId});
  final String? bookId;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  List<ProductDetails> _products = const [];
  String _selected = Products.yearly;
  bool _loading = true;
  bool _buying = false;
  StreamSubscription<String>? _statusSub;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).log(AppEvent.paywallView, {'bookId': widget.bookId});
    final repo = ref.read(subscriptionRepositoryProvider);
    _statusSub = repo.status.listen((s) {
      if (!mounted) return;
      setState(() => _buying = s == 'Processing…');
      if (s == 'success') {
        HapticFeedback.heavyImpact();
        context.pop();
      } else if (s != 'Processing…') {
        showError(context, s);
      }
    });
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    String? bookProduct;
    if (widget.bookId != null) {
      bookProduct = ref.read(bookProvider(widget.bookId!)).value?.productId;
    }
    final products = await ref.read(subscriptionRepositoryProvider).products(bookProductId: bookProduct);
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  ProductDetails? _byId(String id) => _products.where((p) => p.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final ent = ref.watch(entitlementProvider);
    final text = Theme.of(context).textTheme;
    final book = widget.bookId == null ? null : ref.watch(bookProvider(widget.bookId!)).value;
    final bookProduct = book?.productId == null ? null : _byId(book!.productId!);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(),
      body: AuroraBackground(
        accent: Brand.ember,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              ScreenHeader(
                visual: const AnimatedStepIcon(
                  icon: Icons.workspace_premium_rounded,
                  color: Brand.ember,
                  motion: StepIconMotion.rise,
                  size: 100,
                ),
                title: ent.inTrial ? 'Keep your momentum' : 'Unlock Overcome Premium',
                description: ent.inTrial
                    ? 'Your free trial ends in ${ent.trialDaysLeft} day${ent.trialDaysLeft == 1 ? '' : 's'}. Continue without interruption.'
                    : 'The full library, immersive audiobooks and your AI coach — all in one place.',
              ),
              const SizedBox(height: 24),
              for (final (i, f) in const [
                (Icons.library_books_rounded, 'Entire protected library', 'Every book, PDF and audiobook'),
                (Icons.graphic_eq_rounded, 'Read-along audio', 'Live line highlighting as you listen'),
                (Icons.record_voice_over_rounded, 'AI narrator', 'Storyteller, teacher or motivator'),
                (Icons.insights_rounded, 'Adaptive recovery plan', 'Live progress, check-ins and insights'),
              ].indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(f.$1, color: Brand.ember),
                  title: Text(f.$2, style: text.titleSmall),
                  subtitle: Text(f.$3),
                ).animate().fadeIn(delay: (100 * i).ms).slideX(begin: 0.1),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_products.isEmpty)
                const Text('The store is unavailable right now. Please try again later.', textAlign: TextAlign.center)
              else ...[
                for (final id in [Products.yearly, Products.monthly])
                  if (_byId(id) case final p?)
                    _PlanCard(
                      product: p,
                      selected: _selected == id,
                      badge: id == Products.yearly ? 'Best value' : null,
                      onTap: () => setState(() => _selected = id),
                    ),
                const SizedBox(height: 16),
                GradientButton(
                  label: ent.isSubscribed ? 'Change plan' : 'Continue',
                  gradient: Brand.emberGradient,
                  loading: _buying,
                  onPressed: _byId(_selected) == null
                      ? null
                      : () => ref.read(subscriptionRepositoryProvider).buy(_byId(_selected)!),
                ),
                if (bookProduct != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _buying ? null : () => ref.read(subscriptionRepositoryProvider).buy(bookProduct),
                    child: Text('Buy “${book!.title}” only · ${bookProduct.price}'),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(subscriptionRepositoryProvider).restore(),
                child: const Text('Restore purchases'),
              ),
              TextButton(onPressed: () => context.push('/redeem'), child: const Text('Have an unlock code?')),
              Text(
                'Subscriptions renew automatically until cancelled in your store account settings.',
                style: text.labelSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.product, required this.selected, required this.onTap, this.badge});
  final ProductDetails product;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AnimatedContainer(
      duration: Brand.motionFast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        border: Border.all(color: selected ? Brand.ember : Colors.transparent, width: 2),
      ),
      child: GlassCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? Brand.ember : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title.replaceAll(RegExp(r'\s*\(.*\)$'), ''),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(product.description, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(gradient: Brand.emberGradient, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Brand.ink)),
                  ),
                Text(product.price, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
