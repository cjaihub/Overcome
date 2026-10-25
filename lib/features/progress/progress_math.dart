import 'progress_repository.dart';

/// Pure helpers behind the live progress visuals.
abstract final class ProgressMath {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Consecutive days (ending today or yesterday) with at least one check-in.
  static int streak(List<CheckIn> checkIns, {DateTime? now}) {
    final days = {for (final c in checkIns) _day(c.at)};
    var cursor = _day(now ?? DateTime.now());
    if (!days.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(cursor)) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Average headline score per day for the last [days] days (0 when empty).
  static List<double> dailyMood(List<CheckIn> checkIns, {int days = 14, DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    final buckets = List.generate(days, (_) => <num>[]);
    for (final c in checkIns) {
      final idx = days - 1 - today.difference(_day(c.at)).inDays;
      if (idx >= 0 && idx < days && c.mood != null) buckets[idx].add(c.mood!);
    }
    return [for (final b in buckets) b.isEmpty ? 0 : b.reduce((a, b) => a + b) / b.length];
  }

  static int countSince(List<CheckIn> checkIns, Duration window, {String? formId, DateTime? now}) {
    final from = (now ?? DateTime.now()).subtract(window);
    return checkIns.where((c) => c.at.isAfter(from) && (formId == null || c.formId == formId)).length;
  }

  /// Which plan phase the user is in, given when onboarding finished.
  static int phaseIndex(DateTime? startedAt, List<int> phaseWeeks, {DateTime? now}) {
    if (startedAt == null || phaseWeeks.isEmpty) return 0;
    final weeks = (now ?? DateTime.now()).difference(startedAt).inDays ~/ 7;
    var acc = 0;
    for (var i = 0; i < phaseWeeks.length; i++) {
      acc += phaseWeeks[i];
      if (weeks < acc) return i;
    }
    return phaseWeeks.length - 1;
  }
}
