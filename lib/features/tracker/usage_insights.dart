import 'dart:math' as math;

import '../../core/services/usage_service.dart';

/// Pure scoring and insight logic behind the live tracker (unit-tested).
abstract final class UsageInsights {
  /// 0–100: how well today protects the user's attention.
  ///  - screen time over the target costs up to 40 points,
  ///  - unlocks beyond 40/day cost up to 20,
  ///  - late-night use (23:00–06:00) costs up to 25,
  ///  - notification load beyond 100/day costs up to 10,
  ///  - a check-in today earns 5 back.
  static int focusScore(UsageSummary s, {required int targetMinutes, bool checkedIn = false}) {
    final minutes = s.total.inMinutes;
    final over = targetMinutes <= 0 ? 0.0 : math.max(0, minutes - targetMinutes) / targetMinutes;
    var score = 100.0;
    score -= math.min(40, over * 40);
    score -= math.min(20, math.max(0, s.pickups - 40) / 2);
    score -= math.min(25, s.lateNightMinutes / 2);
    score -= math.min(10, math.max(0, s.notifications - 100) / 15);
    if (checkedIn) score += 5;
    return score.clamp(0, 100).round();
  }

  /// Daily target: the onboarding baseline minus the minutes they committed to reclaim.
  static int targetMinutes({required double baselineHours, required int commitMinutes}) =>
      math.max(30, (baselineHours * 60).round() - commitMinutes);

  /// Minutes reclaimed against the onboarding baseline across [days].
  static int reclaimedMinutes(List<UsageSummary> days, double baselineHours) =>
      days.fold(0, (sum, d) => sum + math.max(0, (baselineHours * 60).round() - d.total.inMinutes));

  /// The two consecutive hours with the most use, e.g. (21, 23).
  static (int, int)? peakWindow(UsageSummary s) {
    var best = -1.0;
    var start = -1;
    for (var h = 0; h < 24; h++) {
      final v = s.hourly[h] + s.hourly[(h + 1) % 24];
      if (v > best) {
        best = v;
        start = h;
      }
    }
    return best < 10 ? null : (start, (start + 2) % 24);
  }

  /// Short, actionable observations for the tracker.
  static List<String> insights(UsageSummary s, {required int targetMinutes, Set<String> tracked = const {}}) {
    final out = <String>[];
    String hh(int h) => '${h.toString().padLeft(2, '0')}:00';
    final peak = peakWindow(s);
    if (peak != null) out.add('Most of your screen time today was between ${hh(peak.$1)} and ${hh(peak.$2)}.');
    final noisy = [...s.apps]..sort((a, b) => b.notifications.compareTo(a.notifications));
    if (noisy.isNotEmpty && noisy.first.notifications >= 20) {
      out.add(
        '${noisy.first.label} sent ${noisy.first.notifications} notifications — muting it would cut interruptions.',
      );
    }
    if (s.lateNightMinutes >= 15) {
      out.add('${s.lateNightMinutes.round()} minutes after 23:00. Late scrolling is the biggest drain on sleep.');
    }
    final left = targetMinutes - s.total.inMinutes;
    out.add(left >= 0 ? '$left minutes left before your daily target.' : '${-left} minutes over your target today.');
    final untrackedTop = s.apps.where((a) => !tracked.contains(a.package)).firstOrNull;
    if (untrackedTop != null && untrackedTop.foreground.inMinutes >= 30) {
      out.add('${untrackedTop.label} took ${untrackedTop.foreground.inMinutes} minutes — add it to Guardian?');
    }
    return out;
  }

  static String format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
