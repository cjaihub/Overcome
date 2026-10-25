import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/services/usage_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/common.dart';
import 'guardian_controller.dart';

/// Settings → Guardian mode (real-time usage reminders) and Voice assistant
/// (assistant name, custom wake phrase, hands-free listening).
class GuardianSettingsSection extends ConsumerWidget {
  const GuardianSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(guardianProvider);
    final status = ref.watch(usageStatusProvider).value;
    final name = (ref.watch(userDocProvider).value?['profile'] as Map?)?['displayName'] as String? ?? '';
    final c = ref.read(guardianProvider.notifier);
    void set(GuardianSettings Function(GuardianSettings) f) => c.update(f, userName: name);
    String hh(int h) => '${h.toString().padLeft(2, '0')}:00';

    Future<int?> pickHour(int initial) async => (await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial, minute: 0),
    ))?.hour;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Guardian mode'),
        _Group(
          children: [
            if (status != null && status.supported) ...[
              SwitchListTile(
                secondary: const Icon(Icons.shield_moon_rounded, color: Brand.aurora),
                title: const Text('Real-time reminders'),
                subtitle: const Text('Nudges based on how you use your phone, even when Ovacome is closed'),
                value: g.enabled,
                onChanged: status.usageAccess
                    ? (on) async {
                        if (on) await Permission.notification.request();
                        set((s) => s.copyWith(enabled: on));
                      }
                    : null,
              ),
              if (!status.usageAccess)
                ListTile(
                  leading: const Icon(Icons.lock_open_rounded, color: Brand.ember),
                  title: const Text('Allow usage access first'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => ref.read(usageServiceProvider).openUsageAccessSettings(),
                ),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: const Text('Notification insights'),
                subtitle: Text(
                  status.notificationAccess
                      ? 'On — counts per app only, never message content'
                      : 'Count how many notifications each app sends',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => ref.read(usageServiceProvider).openNotificationAccessSettings(),
              ),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const Text('Watched apps'),
                subtitle: Text(
                  g.tracked.isEmpty ? 'None yet — pick them in Progress → Live' : '${g.tracked.length} apps',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go('/progress'),
              ),
              _SliderTile(
                icon: Icons.timer_rounded,
                label: 'Nudge after a session of',
                value: g.sessionLimitMin,
                min: 5,
                max: 90,
                suffix: 'min',
                onChanged: (v) => set((s) => s.copyWith(sessionLimitMin: v)),
              ),
              _SliderTile(
                icon: Icons.today_rounded,
                label: 'Daily limit for watched apps',
                value: g.dailyLimitMin,
                min: 15,
                max: 300,
                suffix: 'min',
                onChanged: (v) => set((s) => s.copyWith(dailyLimitMin: v)),
              ),
              _SliderTile(
                icon: Icons.lock_open_rounded,
                label: 'Unlock burst (per hour)',
                value: g.pickupBurst,
                min: 5,
                max: 60,
                suffix: 'unlocks',
                onChanged: (v) => set((s) => s.copyWith(pickupBurst: v)),
              ),
              ListTile(
                leading: const Icon(Icons.nightlight_round),
                title: const Text('Late-night window'),
                subtitle: Text('${hh(g.quietStart)} – ${hh(g.quietEnd)}'),
                onTap: () async {
                  final start = await pickHour(g.quietStart);
                  if (start == null) return;
                  final end = await pickHour(g.quietEnd);
                  set((s) => s.copyWith(quietStart: start, quietEnd: end ?? s.quietEnd));
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.record_voice_over_rounded),
                title: const Text('Speak nudges aloud'),
                subtitle: Text('“${name.split(' ').first.isEmpty ? 'Hey' : name.split(' ').first}, you\'ve been on… ”'),
                value: g.voiceNudges,
                onChanged: (v) => set((s) => s.copyWith(voiceNudges: v)),
              ),
            ] else
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Guardian mode needs Android'),
                subtitle: Text('iOS keeps app usage private to Apple\'s Screen Time.'),
              ),
          ],
        ),
        const SectionTitle('Voice assistant'),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_rounded),
              title: const Text('Assistant name'),
              subtitle: Text(g.assistantName),
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: () async {
                final v = await _prompt(context, 'Assistant name', g.assistantName, 'e.g. Ova, Nova, Coach');
                if (v != null && v.trim().isNotEmpty) set((s) => s.copyWith(assistantName: v.trim()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.hearing_rounded),
              title: const Text('Wake phrase'),
              subtitle: Text(
                g.wakePhrase.isEmpty ? '“${g.effectiveWakePhrase(name)}” (your name — default)' : '“${g.wakePhrase}”',
              ),
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: () async {
                final v = await _prompt(context, 'Wake phrase', g.wakePhrase, 'Leave empty to use your first name');
                if (v != null) set((s) => s.copyWith(wakePhrase: v.trim()));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.mic_rounded),
              title: const Text('Hands-free'),
              subtitle: const Text('Listen for the wake phrase while Ovacome is open'),
              value: g.handsFree,
              onChanged: (v) async {
                if (v && !await Permission.microphone.request().isGranted) return;
                set((s) => s.copyWith(handsFree: v));
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<String?> _prompt(BuildContext context, String title, String initial, String hint) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text('$label · $value $suffix'),
    subtitle: Slider(
      value: value.clamp(min, max).toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: max - min,
      onChanged: (v) => onChanged(v.round()),
    ),
  );
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
