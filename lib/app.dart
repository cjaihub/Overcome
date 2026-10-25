import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/brand.dart';
import 'core/widgets/animated_step_icon.dart';
import 'core/widgets/aurora_background.dart';
import 'features/settings/settings_controller.dart';

class OvercomeApp extends ConsumerWidget {
  const OvercomeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => _AppLock(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Optional biometric lock shown on launch and whenever the app returns
/// from the background.
class _AppLock extends ConsumerStatefulWidget {
  const _AppLock({required this.child});
  final Widget child;

  @override
  ConsumerState<_AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<_AppLock> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  late bool _locked = ref.read(settingsProvider).biometricLock;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(settingsProvider).biometricLock || _prompting) return;
    if (state == AppLifecycleState.paused) setState(() => _locked = true);
    if (state == AppLifecycleState.resumed && _locked) _unlock();
  }

  Future<void> _unlock() async {
    _prompting = true;
    try {
      final ok = await _auth.authenticate(localizedReason: 'Unlock ${Brand.name}', persistAcrossBackgrounding: true);
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Leave locked; the user can retry from the lock screen.
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_locked)
        Positioned.fill(
          child: AuroraBackground(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AnimatedStepIcon(icon: Icons.lock_rounded, motion: StepIconMotion.breathe),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
                    onPressed: _unlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
