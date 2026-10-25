import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppUsage {
  const AppUsage({
    required this.package,
    required this.label,
    required this.foreground,
    required this.launches,
    required this.notifications,
    this.icon,
  });

  final String package;
  final String label;
  final Duration foreground;
  final int launches;
  final int notifications;
  final Uint8List? icon;

  factory AppUsage.fromMap(Map<dynamic, dynamic> m) => AppUsage(
    package: m['package'] as String,
    label: m['label'] as String,
    foreground: Duration(milliseconds: (m['foregroundMs'] as num).toInt()),
    launches: (m['launches'] as num).toInt(),
    notifications: (m['notifications'] as num?)?.toInt() ?? 0,
    icon: m['icon'] as Uint8List?,
  );
}

/// One day (or partial day) of real device usage.
class UsageSummary {
  const UsageSummary({
    required this.day,
    required this.total,
    required this.screenOn,
    required this.pickups,
    required this.notifications,
    required this.hourly,
    required this.hourlyNotifications,
    required this.apps,
  });

  final DateTime day;
  final Duration total;
  final Duration screenOn;
  final int pickups;
  final int notifications;

  /// Minutes of app use in each hour 0–23.
  final List<double> hourly;
  final List<int> hourlyNotifications;
  final List<AppUsage> apps;

  static const lateNightHours = {23, 0, 1, 2, 3, 4, 5};

  double get lateNightMinutes => [for (final h in lateNightHours) hourly[h]].fold(0, (a, b) => a + b);

  Duration trackedTotal(Set<String> tracked) =>
      apps.where((a) => tracked.contains(a.package)).fold(Duration.zero, (a, b) => a + b.foreground);

  factory UsageSummary.fromMap(DateTime day, Map<dynamic, dynamic> m) => UsageSummary(
    day: day,
    total: Duration(milliseconds: (m['totalMs'] as num).toInt()),
    screenOn: Duration(milliseconds: (m['screenOnMs'] as num).toInt()),
    pickups: (m['pickups'] as num).toInt(),
    notifications: (m['notifications'] as num?)?.toInt() ?? 0,
    hourly: [for (final v in m['hourlyMs'] as List) (v as num) / 60000],
    hourlyNotifications: [for (final v in m['hourlyNotifications'] as List) (v as num).toInt()],
    apps: [for (final a in m['apps'] as List) AppUsage.fromMap(a as Map)],
  );
}

class CurrentSession {
  const CurrentSession(this.package, this.label, this.since);
  final String package;
  final String label;
  final DateTime since;
}

class UsageStatus {
  const UsageStatus({required this.supported, this.usageAccess = false, this.notificationAccess = false});
  final bool supported;
  final bool usageAccess;
  final bool notificationAccess;
}

/// Real device usage from Android's usage-events log (and notification
/// counts from the listener service). iOS restricts this data to apps with
/// Apple's Family Controls entitlement, so it reports `supported: false`
/// there and the tracker falls back to check-ins and in-app activity.
class UsageService {
  static const _ch = MethodChannel('ovacome/usage');

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<UsageStatus> status() async {
    if (!supported) return const UsageStatus(supported: false);
    final m = await _ch.invokeMapMethod<String, dynamic>('status') ?? const {};
    return UsageStatus(
      supported: true,
      usageAccess: m['usageAccess'] == true,
      notificationAccess: m['notificationAccess'] == true,
    );
  }

  Future<void> openUsageAccessSettings() => _ch.invokeMethod('openUsageAccessSettings');
  Future<void> openNotificationAccessSettings() => _ch.invokeMethod('openNotificationAccessSettings');

  Future<UsageSummary> day(DateTime day, {bool icons = false}) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('summary', {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'icons': icons,
    });
    return UsageSummary.fromMap(start, m!);
  }

  Future<CurrentSession?> current() async {
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('current');
    if (m == null) return null;
    return CurrentSession(
      m['package'] as String,
      m['label'] as String,
      DateTime.fromMillisecondsSinceEpoch((m['since'] as num).toInt()),
    );
  }

  Future<void> configureGuardian(Map<String, Object?> config) =>
      _ch.invokeMethod('configureGuardian', {'config': jsonEncode(config)});

  /// Nudges the native Guardian sent since the last call (for analytics).
  Future<List<Map<String, dynamic>>> drainNudges() async {
    final raw = await _ch.invokeMethod<String>('drainNudges') ?? '[]';
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }
}

final usageServiceProvider = Provider<UsageService>((_) => UsageService());

/// Re-checked whenever the app resumes (the user may have just granted access).
final usageStatusProvider = FutureProvider<UsageStatus>((ref) => ref.watch(usageServiceProvider).status());

/// Today's usage, refreshed every 15 seconds while watched.
final liveUsageProvider = StreamProvider.autoDispose<UsageSummary?>((ref) async* {
  final svc = ref.watch(usageServiceProvider);
  final status = await ref.watch(usageStatusProvider.future);
  if (!status.usageAccess) {
    yield null;
    return;
  }
  while (true) {
    yield await svc.day(DateTime.now(), icons: true);
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});

/// The app in the foreground right now (polled every 10 s).
final currentSessionProvider = StreamProvider.autoDispose<CurrentSession?>((ref) async* {
  final svc = ref.watch(usageServiceProvider);
  final status = await ref.watch(usageStatusProvider.future);
  if (!status.usageAccess) return;
  while (true) {
    yield await svc.current();
    await Future<void>.delayed(const Duration(seconds: 10));
  }
});

/// The previous 7 full days plus today, oldest first.
final weekUsageProvider = FutureProvider.autoDispose<List<UsageSummary>>((ref) async {
  final svc = ref.watch(usageServiceProvider);
  final status = await ref.watch(usageStatusProvider.future);
  if (!status.usageAccess) return const [];
  final now = DateTime.now();
  return [for (var i = 7; i >= 0; i--) await svc.day(now.subtract(Duration(days: i)))];
});
