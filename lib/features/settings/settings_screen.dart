import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_repository.dart';
import '../subscription/entitlement.dart';
import '../tracker/guardian_settings_section.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final ent = ref.watch(entitlementProvider);
    final user = ref.watch(authStateProvider).value;
    final isAdmin = ref.watch(isAdminProvider);
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Text('Settings', style: text.headlineMedium),
        const SizedBox(height: 16),
        GlassCard(
          gradient: Brand.auroraGradient,
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                child: Text(
                  (user?.displayName ?? '?').characters.first.toUpperCase(),
                  style: text.titleLarge?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.displayName ?? 'You', style: text.titleLarge?.copyWith(color: Brand.ink)),
                    Text(
                      user?.phoneNumber ?? '',
                      style: text.bodyMedium?.copyWith(color: Brand.ink.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 4),
                    Text(ent.label, style: text.labelLarge?.copyWith(color: Brand.ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Membership'),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.workspace_premium_rounded),
              title: Text(ent.isSubscribed ? 'Manage subscription' : 'Upgrade to Premium'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/paywall'),
            ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: const Text('Redeem a code'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/redeem'),
            ),
          ],
        ),
        const SectionTitle('Appearance'),
        _Group(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_iphone_rounded), label: Text('Auto')),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => c.setThemeMode(v.first),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Haptic feedback'),
              value: s.haptics,
              onChanged: c.setHaptics,
            ),
          ],
        ),
        const SectionTitle('Check-ins & reminders'),
        _Group(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_rounded),
              title: const Text('Daily check-in reminder'),
              subtitle: Text('Every day at ${s.reminderHour.toString().padLeft(2, '0')}:00'),
              value: s.reminders,
              onChanged: (on) async {
                if (on) await FirebaseMessaging.instance.requestPermission();
                c.setReminders(on);
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Reminder time'),
              enabled: s.reminders,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: s.reminderHour, minute: 0),
                );
                if (t != null) c.setReminders(true, hour: t.hour);
              },
            ),
          ],
        ),
        const GuardianSettingsSection(),
        const SectionTitle('Reading & listening'),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.record_voice_over_rounded),
              title: const Text('Default AI narrator'),
              trailing: DropdownButton<String>(
                value: s.narrator,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'storyteller', child: Text('Storyteller')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                  DropdownMenuItem(value: 'motivator', child: Text('Motivator')),
                ],
                onChanged: (v) => v == null ? null : c.setNarrator(v),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text('Narration speed · ${s.voiceSpeed.toStringAsFixed(1)}×'),
              subtitle: Slider(value: s.voiceSpeed, min: 0.6, max: 1.6, divisions: 10, onChanged: c.setVoiceSpeed),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.headphones_rounded),
              title: const Text('Keep playing in background'),
              subtitle: const Text('Audiobooks continue with lock-screen controls'),
              value: s.backgroundAudio,
              onChanged: c.setBackgroundAudio,
            ),
          ],
        ),
        const SectionTitle('Privacy & security'),
        _Group(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Biometric app lock'),
              value: s.biometricLock,
              onChanged: (on) async {
                if (on) {
                  final ok = await LocalAuthentication().authenticate(localizedReason: 'Confirm to enable app lock');
                  if (!ok) return;
                }
                c.setBiometricLock(on);
              },
            ),
            const ListTile(
              leading: Icon(Icons.shield_rounded, color: Brand.aurora),
              title: Text('Content protection is always on'),
              subtitle: Text(
                'Screenshots, recording, sharing, printing and downloads are blocked for library content.',
              ),
            ),
          ],
        ),
        if (isAdmin) ...[
          const SectionTitle('Owner'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.insights_rounded, color: Brand.ember),
                title: const Text('Admin dashboard'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/admin'),
              ),
            ],
          ),
        ],
        const SectionTitle('Account'),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Brand.danger),
              title: const Text('Delete account', style: TextStyle(color: Brand.danger)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete your account?'),
                    content: const Text('Your progress, plan and purchases will be permanently removed.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) await ref.read(authRepositoryProvider).deleteAccount();
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(child: Image.asset(BrandAssets.horizontal(Theme.of(context).brightness), height: 28)),
        const SizedBox(height: 6),
        Center(child: Text('v1.0.0', style: text.labelSmall)),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(children: children),
  );
}
