import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/usage_service.dart';
import '../settings/settings_controller.dart';

/// Guardian mode (real-time usage nudges) and voice-assistant preferences.
class GuardianSettings {
  const GuardianSettings({
    this.enabled = false,
    this.tracked = const {},
    this.sessionLimitMin = 20,
    this.dailyLimitMin = 90,
    this.quietStart = 23,
    this.quietEnd = 6,
    this.pickupBurst = 20,
    this.voiceNudges = true,
    this.assistantName = 'Ova',
    this.wakePhrase = '',
    this.handsFree = false,
  });

  final bool enabled;

  /// Package names of the apps Guardian watches.
  final Set<String> tracked;
  final int sessionLimitMin;
  final int dailyLimitMin;
  final int quietStart;
  final int quietEnd;
  final int pickupBurst;

  /// Speak nudges aloud (in addition to the notification).
  final bool voiceNudges;

  /// What the coach is called in chat and in spoken replies.
  final String assistantName;

  /// Word(s) that wake the voice coach hands-free. Empty = the user's first name.
  final String wakePhrase;
  final bool handsFree;

  String effectiveWakePhrase(String userName) => wakePhrase.trim().isNotEmpty
      ? wakePhrase.trim()
      : (userName.split(' ').first.trim().isEmpty ? assistantName : userName.split(' ').first);

  GuardianSettings copyWith({
    bool? enabled,
    Set<String>? tracked,
    int? sessionLimitMin,
    int? dailyLimitMin,
    int? quietStart,
    int? quietEnd,
    int? pickupBurst,
    bool? voiceNudges,
    String? assistantName,
    String? wakePhrase,
    bool? handsFree,
  }) => GuardianSettings(
    enabled: enabled ?? this.enabled,
    tracked: tracked ?? this.tracked,
    sessionLimitMin: sessionLimitMin ?? this.sessionLimitMin,
    dailyLimitMin: dailyLimitMin ?? this.dailyLimitMin,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    pickupBurst: pickupBurst ?? this.pickupBurst,
    voiceNudges: voiceNudges ?? this.voiceNudges,
    assistantName: assistantName ?? this.assistantName,
    wakePhrase: wakePhrase ?? this.wakePhrase,
    handsFree: handsFree ?? this.handsFree,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'tracked': tracked.toList(),
    'sessionLimitMin': sessionLimitMin,
    'dailyLimitMin': dailyLimitMin,
    'quietStart': quietStart,
    'quietEnd': quietEnd,
    'pickupBurst': pickupBurst,
    'voice': voiceNudges,
    'assistantName': assistantName,
    'wakePhrase': wakePhrase,
    'handsFree': handsFree,
  };

  factory GuardianSettings.fromJson(Map<String, dynamic> j) => GuardianSettings(
    enabled: j['enabled'] as bool? ?? false,
    tracked: {...?(j['tracked'] as List?)?.cast<String>()},
    sessionLimitMin: j['sessionLimitMin'] as int? ?? 20,
    dailyLimitMin: j['dailyLimitMin'] as int? ?? 90,
    quietStart: j['quietStart'] as int? ?? 23,
    quietEnd: j['quietEnd'] as int? ?? 6,
    pickupBurst: j['pickupBurst'] as int? ?? 20,
    voiceNudges: j['voice'] as bool? ?? true,
    assistantName: j['assistantName'] as String? ?? 'Ova',
    wakePhrase: j['wakePhrase'] as String? ?? '',
    handsFree: j['handsFree'] as bool? ?? false,
  );
}

class GuardianController extends Notifier<GuardianSettings> {
  static const _key = 'guardian';

  @override
  GuardianSettings build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    return raw == null ? const GuardianSettings() : GuardianSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Persists locally and pushes the config to the native Guardian service.
  Future<void> update(GuardianSettings Function(GuardianSettings) f, {String userName = ''}) async {
    state = f(state);
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state.toJson()));
    final usage = ref.read(usageServiceProvider);
    if (usage.supported) {
      await usage.configureGuardian({...state.toJson(), 'userName': userName.split(' ').first});
    }
  }

  Future<void> toggleTracked(String pkg, {String userName = ''}) => update(
    (s) => s.copyWith(tracked: s.tracked.contains(pkg) ? ({...s.tracked}..remove(pkg)) : {...s.tracked, pkg}),
    userName: userName,
  );
}

final guardianProvider = NotifierProvider<GuardianController, GuardianSettings>(GuardianController.new);
