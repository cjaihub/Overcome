import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import 'auth_repository.dart';

/// Redeems a one-time unlock code that ships with a purchased book or is
/// issued by a counselor / organization. Codes are single-use and bound to
/// the signed-in account (and optionally to a phone number) server side.
class RedeemCodeScreen extends ConsumerStatefulWidget {
  const RedeemCodeScreen({super.key});

  @override
  ConsumerState<RedeemCodeScreen> createState() => _RedeemCodeScreenState();
}

class _RedeemCodeScreenState extends ConsumerState<RedeemCodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _success;

  Future<void> _redeem() async {
    setState(() => _busy = true);
    try {
      final message = await ref.read(authRepositoryProvider).redeemCode(_code.text);
      ref.read(analyticsProvider).log(AppEvent.codeRedeemed);
      HapticFeedback.heavyImpact();
      setState(() => _success = message);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _success != null;
    return Scaffold(
      appBar: AppBar(),
      extendBodyBehindAppBar: true,
      body: AuroraBackground(
        accent: ok ? Brand.success : Brand.ember,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ScreenHeader(
                key: ValueKey(ok),
                visual: AnimatedStepIcon(
                  icon: ok ? Icons.verified_rounded : Icons.key_rounded,
                  motion: ok ? StepIconMotion.rise : StepIconMotion.orbit,
                  color: ok ? Brand.success : Brand.ember,
                ),
                title: ok ? 'Unlocked' : 'Redeem your code',
                description: ok ? _success! : 'Enter the one-time code from your book or your counselor.',
              ),
              const SizedBox(height: 32),
              if (!ok) ...[
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                    LengthLimitingTextInputFormatter(19),
                  ],
                  decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                GradientButton(
                  label: 'Unlock',
                  gradient: Brand.emberGradient,
                  loading: _busy,
                  onPressed: _code.text.length >= 8 ? _redeem : null,
                ),
              ] else
                GradientButton(label: 'Continue', onPressed: () => context.go('/')),
            ],
          ),
        ),
      ),
    );
  }
}
