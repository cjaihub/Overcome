import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` once SharedPreferences has loaded.
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.reminders = true,
    this.reminderHour = 20,
    this.narrator = 'teacher',
    this.voiceSpeed = 1.0,
    this.biometricLock = false,
    this.backgroundAudio = true,
    this.haptics = true,
  });

  final ThemeMode themeMode;
  final bool reminders;
  final int reminderHour;
  final String narrator;
  final double voiceSpeed;
  final bool biometricLock;
  final bool backgroundAudio;
  final bool haptics;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? reminders,
    int? reminderHour,
    String? narrator,
    double? voiceSpeed,
    bool? biometricLock,
    bool? backgroundAudio,
    bool? haptics,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    reminders: reminders ?? this.reminders,
    reminderHour: reminderHour ?? this.reminderHour,
    narrator: narrator ?? this.narrator,
    voiceSpeed: voiceSpeed ?? this.voiceSpeed,
    biometricLock: biometricLock ?? this.biometricLock,
    backgroundAudio: backgroundAudio ?? this.backgroundAudio,
    haptics: haptics ?? this.haptics,
  );
}

class SettingsController extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    return AppSettings(
      themeMode: ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.dark.index],
      reminders: p.getBool('reminders') ?? true,
      reminderHour: p.getInt('reminderHour') ?? 20,
      narrator: p.getString('narrator') ?? 'teacher',
      voiceSpeed: p.getDouble('voiceSpeed') ?? 1.0,
      biometricLock: p.getBool('biometricLock') ?? false,
      backgroundAudio: p.getBool('backgroundAudio') ?? true,
      haptics: p.getBool('haptics') ?? true,
    );
  }

  void setThemeMode(ThemeMode m) {
    _prefs.setInt('themeMode', m.index);
    state = state.copyWith(themeMode: m);
  }

  void setReminders(bool on, {int? hour}) {
    _prefs.setBool('reminders', on);
    if (hour != null) _prefs.setInt('reminderHour', hour);
    state = state.copyWith(reminders: on, reminderHour: hour);
    _syncServer();
  }

  void setNarrator(String n) {
    _prefs.setString('narrator', n);
    state = state.copyWith(narrator: n);
  }

  void setVoiceSpeed(double v) {
    _prefs.setDouble('voiceSpeed', v);
    state = state.copyWith(voiceSpeed: v);
  }

  void setBiometricLock(bool on) {
    _prefs.setBool('biometricLock', on);
    state = state.copyWith(biometricLock: on);
  }

  void setBackgroundAudio(bool on) {
    _prefs.setBool('backgroundAudio', on);
    state = state.copyWith(backgroundAudio: on);
  }

  void setHaptics(bool on) {
    _prefs.setBool('haptics', on);
    state = state.copyWith(haptics: on);
  }

  /// The `dailyNudge` scheduled function reads these to send check-in pushes.
  Future<void> _syncServer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.doc('users/$uid').set({
      'settings': {
        'reminders': state.reminders,
        'reminderHour': state.reminderHour,
        // The server sends reminders by UTC hour.
        'reminderUtcHour': (state.reminderHour - DateTime.now().timeZoneOffset.inMinutes / 60).round() % 24,
      },
    }, SetOptions(merge: true));
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
