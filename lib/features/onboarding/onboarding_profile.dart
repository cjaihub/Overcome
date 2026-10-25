/// Everything the wizard learns about the user. Persisted as a draft after
/// every change so onboarding can be resumed on any device.
class OnboardingProfile {
  const OnboardingProfile({
    this.displayName = '',
    this.role = 'individual',
    this.identity = '',
    this.habits = const [],
    this.dailyHours = 4,
    this.peakTimes = const [],
    this.triggers = const [],
    this.goals = const [],
    this.coachStyle = 'teacher',
    this.dailyMinutesGoal = 45,
  });

  final String displayName;

  /// individual | counselor | supporter
  final String role;
  final String identity;
  final List<String> habits;
  final double dailyHours;
  final List<String> peakTimes;
  final List<String> triggers;
  final List<String> goals;

  /// storyteller | teacher | motivator — also the default AI narrator voice.
  final String coachStyle;

  /// Minutes per day the user commits to reclaim.
  final int dailyMinutesGoal;

  static const habitOptions = [
    'Social media',
    'Short videos',
    'Gaming',
    'News scrolling',
    'Messaging',
    'Online shopping',
    'Streaming',
    'Adult content',
    'Gambling',
    'Email & work apps',
  ];

  static const triggerOptions = [
    'Boredom',
    'Stress',
    'Loneliness',
    'Anxiety',
    'Procrastination',
    'Tiredness',
    'FOMO',
    'Notifications',
    'Conflict',
    'Late nights',
  ];

  static const goalOptions = [
    'Deep focus',
    'Better sleep',
    'Present with family',
    'Fitness',
    'Learn a skill',
    'Creativity',
    'Calmer mind',
    'Career growth',
  ];

  static const peakOptions = ['Morning', 'Midday', 'Evening', 'Late night'];

  static const identityOptions = [
    'I am someone who is present.',
    'I am someone who finishes what they start.',
    'I am someone who protects their focus.',
    'I am someone who chooses real connection.',
  ];

  /// 0–100 composite used for template matching and the live gauge.
  int get severity {
    final hours = (dailyHours / 12).clamp(0, 1) * 55;
    final breadth = (habits.length / 5).clamp(0, 1) * 25;
    final triggerLoad = (triggers.length / 6).clamp(0, 1) * 20;
    return (hours + breadth + triggerLoad).round();
  }

  String get severityBand => severity < 35 ? 'mild' : (severity < 65 ? 'moderate' : 'high');

  double get hoursPerYear => dailyHours * 365;

  OnboardingProfile copyWith({
    String? displayName,
    String? role,
    String? identity,
    List<String>? habits,
    double? dailyHours,
    List<String>? peakTimes,
    List<String>? triggers,
    List<String>? goals,
    String? coachStyle,
    int? dailyMinutesGoal,
  }) => OnboardingProfile(
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    identity: identity ?? this.identity,
    habits: habits ?? this.habits,
    dailyHours: dailyHours ?? this.dailyHours,
    peakTimes: peakTimes ?? this.peakTimes,
    triggers: triggers ?? this.triggers,
    goals: goals ?? this.goals,
    coachStyle: coachStyle ?? this.coachStyle,
    dailyMinutesGoal: dailyMinutesGoal ?? this.dailyMinutesGoal,
  );

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'role': role,
    'identity': identity,
    'habits': habits,
    'dailyHours': dailyHours,
    'peakTimes': peakTimes,
    'triggers': triggers,
    'goals': goals,
    'coachStyle': coachStyle,
    'dailyMinutesGoal': dailyMinutesGoal,
    'severity': severity,
    'severityBand': severityBand,
  };

  factory OnboardingProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const OnboardingProfile();
    List<String> list(String k) => (m[k] as List?)?.cast<String>() ?? const [];
    return OnboardingProfile(
      displayName: m['displayName'] as String? ?? '',
      role: m['role'] as String? ?? 'individual',
      identity: m['identity'] as String? ?? '',
      habits: list('habits'),
      dailyHours: (m['dailyHours'] as num?)?.toDouble() ?? 4,
      peakTimes: list('peakTimes'),
      triggers: list('triggers'),
      goals: list('goals'),
      coachStyle: m['coachStyle'] as String? ?? 'teacher',
      dailyMinutesGoal: (m['dailyMinutesGoal'] as num?)?.toInt() ?? 45,
    );
  }
}
