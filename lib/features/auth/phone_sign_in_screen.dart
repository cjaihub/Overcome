import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import 'auth_repository.dart';

/// Phone number → live SMS one-time code → signed in.
class PhoneSignInScreen extends ConsumerStatefulWidget {
  const PhoneSignInScreen({super.key, this.next});
  final String? next;

  @override
  ConsumerState<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends ConsumerState<PhoneSignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String _dial = '+1';
  CodeSent? _sent;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;

  static const _dialCodes = ['+1', '+44', '+33', '+49', '+234', '+254', '+27', '+250', '+91', '+971', '+61'];

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _e164 => '$_dial${_phone.text.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _send({bool resend = false}) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(authRepositoryProvider).sendCode(_e164, resendToken: resend ? _sent?.resendToken : null);
      if (!mounted) return;
      switch (r) {
        case CodeSent():
          setState(() => _sent = r);
          _startCountdown();
        case AutoVerified():
          _done();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _resendIn = 45;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (_code.text.length != 6 || _sent == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).confirmCode(_sent!.verificationId, _code.text);
      _done();
    } catch (e) {
      if (mounted) showError(context, e);
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    context.go(widget.next ?? '/');
  }

  @override
  Widget build(BuildContext context) {
    final codeStage = _sent != null;
    return Scaffold(
      appBar: AppBar(),
      extendBodyBehindAppBar: true,
      body: AuroraBackground(
        accent: codeStage ? Brand.iris : Brand.aurora,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              AnimatedSwitcher(
                duration: Brand.motion,
                child: ScreenHeader(
                  key: ValueKey(codeStage),
                  visual: AnimatedStepIcon(
                    icon: codeStage ? Icons.sms_rounded : Icons.phone_iphone_rounded,
                    motion: codeStage ? StepIconMotion.wave : StepIconMotion.pulse,
                    color: codeStage ? Brand.iris : Brand.aurora,
                  ),
                  title: codeStage ? 'Enter your code' : 'Your phone number',
                  description: codeStage
                      ? 'We sent a 6-digit code to $_e164. It verifies this device is yours.'
                      : 'Your number is your secure identity. We\'ll text a one-time code — no passwords.',
                ),
              ),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: Brand.motion,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.1, 0), end: Offset.zero).animate(a),
                    child: c,
                  ),
                ),
                child: codeStage ? _codeInput() : _phoneInput(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneInput() => Column(
    key: const ValueKey('phone'),
    children: [
      Row(
        children: [
          DropdownMenu<String>(
            width: 110,
            initialSelection: _dial,
            onSelected: (v) => setState(() => _dial = v ?? _dial),
            dropdownMenuEntries: [for (final d in _dialCodes) DropdownMenuEntry(value: d, label: d)],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: const InputDecoration(hintText: 'Phone number'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      GradientButton(
        label: 'Send code',
        icon: Icons.arrow_forward_rounded,
        loading: _busy,
        onPressed: _phone.text.replaceAll(RegExp(r'\D'), '').length >= 6 ? _send : null,
      ),
    ],
  );

  Widget _codeInput() => Column(
    key: const ValueKey('code'),
    children: [
      _OtpBoxes(controller: _code, onCompleted: _verify),
      const SizedBox(height: 24),
      GradientButton(label: 'Verify', loading: _busy, onPressed: _code.text.length == 6 ? _verify : null),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _resendIn > 0 || _busy ? null : () => _send(resend: true),
        child: Text(_resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code'),
      ),
      TextButton(onPressed: () => setState(() => _sent = null), child: const Text('Change number')),
    ],
  );
}

/// Six animated boxes backed by one hidden text field (keeps SMS autofill).
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({required this.controller, required this.onCompleted});
  final TextEditingController controller;
  final VoidCallback onCompleted;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              onChanged: (v) {
                setState(() {});
                if (v.length == 6) widget.onCompleted();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 6; i++)
                AnimatedContainer(
                  duration: Brand.motionFast,
                  width: 48,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: i == text.length ? Brand.iris : (i < text.length ? Brand.aurora : Colors.transparent),
                      width: 1.6,
                    ),
                  ),
                  child: i < text.length
                      ? Text(
                          text[i],
                          style: Theme.of(context).textTheme.headlineSmall,
                        ).animate().scale(duration: Brand.motionFast, curve: Curves.easeOutBack)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
