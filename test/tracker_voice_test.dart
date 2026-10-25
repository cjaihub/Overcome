import 'package:flutter_test/flutter_test.dart';
import 'package:overcome/core/services/usage_service.dart';
import 'package:overcome/features/coach/voice_engine.dart';
import 'package:overcome/features/tracker/guardian_controller.dart';
import 'package:overcome/features/tracker/usage_insights.dart';

UsageSummary _day({int minutes = 120, int pickups = 30, int notifications = 50, Map<int, double> hourly = const {}}) =>
    UsageSummary(
      day: DateTime(2026, 10, 25),
      total: Duration(minutes: minutes),
      screenOn: Duration(minutes: minutes + 20),
      pickups: pickups,
      notifications: notifications,
      hourly: [for (var h = 0; h < 24; h++) hourly[h] ?? 0],
      hourlyNotifications: List.filled(24, 0),
      apps: [
        AppUsage(
          package: 'com.social',
          label: 'Social',
          foreground: Duration(minutes: minutes ~/ 2),
          launches: 40,
          notifications: 30,
        ),
        AppUsage(
          package: 'com.video',
          label: 'Video',
          foreground: Duration(minutes: minutes ~/ 2),
          launches: 10,
          notifications: 2,
        ),
      ],
    );

void main() {
  group('UsageInsights', () {
    test('a calm day under target scores 100; a heavy late night scores low', () {
      expect(UsageInsights.focusScore(_day(minutes: 60), targetMinutes: 120), 100);
      final heavy = _day(minutes: 360, pickups: 120, notifications: 300, hourly: {0: 60, 1: 50});
      expect(UsageInsights.focusScore(heavy, targetMinutes: 120), lessThan(25));
    });

    test('checking in earns points back but never exceeds 100', () {
      final d = _day(minutes: 180);
      expect(
        UsageInsights.focusScore(d, targetMinutes: 120, checkedIn: true),
        UsageInsights.focusScore(d, targetMinutes: 120) + 5,
      );
      expect(UsageInsights.focusScore(_day(minutes: 10), targetMinutes: 120, checkedIn: true), 100);
    });

    test('target subtracts the commitment from the baseline, with a floor', () {
      expect(UsageInsights.targetMinutes(baselineHours: 4, commitMinutes: 60), 180);
      expect(UsageInsights.targetMinutes(baselineHours: 0.5, commitMinutes: 60), 30);
    });

    test('reclaimed minutes count only days under the baseline', () {
      expect(UsageInsights.reclaimedMinutes([_day(minutes: 200), _day(minutes: 300)], 4), 40);
    });

    test('peak window finds the busiest two hours', () {
      expect(UsageInsights.peakWindow(_day(hourly: {21: 40, 22: 35, 9: 10})), (21, 23));
      expect(UsageInsights.peakWindow(_day()), isNull);
    });

    test('insights flag noisy apps and suggest watching heavy untracked apps', () {
      final lines = UsageInsights.insights(_day(minutes: 200), targetMinutes: 120);
      expect(lines.any((l) => l.contains('Social sent 30 notifications')), isTrue);
      expect(lines.any((l) => l.contains('80 minutes over')), isTrue);
      expect(lines.any((l) => l.contains('add it to Guardian')), isTrue);
    });
  });

  group('WakeMatcher', () {
    test('matches the wake phrase inside a sentence, case-insensitive', () {
      expect(WakeMatcher.matches('hey Amara are you there', 'Amara'), isTrue);
      expect(WakeMatcher.matches('okay NOVA', 'nova'), isTrue);
    });

    test('tolerates small recognizer misspellings of longer names', () {
      expect(WakeMatcher.matches('amarah help me', 'Amara'), isTrue);
      expect(WakeMatcher.matches('hello abdul', 'Abdoul'), isTrue);
    });

    test('multi-word phrases must appear in order', () {
      expect(WakeMatcher.matches('hey there coach ova', 'coach ova'), isTrue);
      expect(WakeMatcher.matches('ova coach', 'coach ova'), isFalse);
    });

    test('rejects unrelated speech and short-name near misses', () {
      expect(WakeMatcher.matches('what a lovely day', 'Amara'), isFalse);
      expect(WakeMatcher.matches('ava', 'Ova'), isFalse);
    });
  });

  test('voice cues: fast agitated speech vs slow hesitant speech', () {
    final agitated = VoiceSample.fromLevels(List.filled(50, 'word').join(' '), const Duration(seconds: 15), [
      for (var i = 0; i < 60; i++) i.isEven ? 9.0 : 1.0,
    ]);
    final hesitant = VoiceSample.fromLevels('I just feel tired', const Duration(seconds: 10), [
      for (var i = 0; i < 60; i++) i % 5 == 0 ? 6.0 : 0.0,
    ]);
    expect(agitated.wordsPerMinute, 200);
    expect(agitated.loudnessVariation, greaterThan(0.8));
    expect(hesitant.wordsPerMinute, closeTo(24, 0.1));
    expect(hesitant.pauseRatio, greaterThan(0.7));
  });

  test('wake phrase defaults to the first name and can be customised', () {
    const g = GuardianSettings();
    expect(g.effectiveWakePhrase('Amara Okafor'), 'Amara');
    expect(g.copyWith(wakePhrase: 'Hey Nova').effectiveWakePhrase('Amara Okafor'), 'Hey Nova');
    expect(g.effectiveWakePhrase(''), 'Ova');
  });
}
