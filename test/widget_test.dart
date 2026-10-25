import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overcome/core/widgets/live_infographics.dart';
import 'package:overcome/features/library/book.dart';
import 'package:overcome/features/library/book_3d.dart';
import 'package:overcome/features/library/library_repository.dart';
import 'package:overcome/features/onboarding/onboarding_profile.dart';
import 'package:overcome/features/progress/progress_math.dart';
import 'package:overcome/features/progress/progress_repository.dart';
import 'package:overcome/features/progress/recovery_plan.dart';
import 'package:overcome/features/subscription/entitlement.dart';

CheckIn _c(DateTime at, {num? mood, String form = 'daily_check_in'}) =>
    CheckIn(formId: form, answers: const {}, at: at, mood: mood);

const _book = Book(
  id: 'b1',
  title: 'The Quiet Mind',
  author: 'A. Author',
  description: 'A book about attention.',
  category: 'Focus',
  coverUrl: '',
  accent: 'iris',
  pages: 200,
  audioMinutes: 300,
  hasPdf: true,
  hasAudio: true,
  featured: true,
);

void main() {
  group('ProgressMath', () {
    final now = DateTime(2026, 10, 25, 12);

    test('streak counts consecutive days ending today', () {
      final c = [for (var i = 0; i < 4; i++) _c(now.subtract(Duration(days: i)))];
      expect(ProgressMath.streak(c, now: now), 4);
    });

    test('streak survives if today is not logged yet', () {
      final c = [_c(now.subtract(const Duration(days: 1))), _c(now.subtract(const Duration(days: 2)))];
      expect(ProgressMath.streak(c, now: now), 2);
    });

    test('streak breaks on a gap', () {
      final c = [_c(now), _c(now.subtract(const Duration(days: 2)))];
      expect(ProgressMath.streak(c, now: now), 1);
    });

    test('dailyMood averages per day and leaves empty days at zero', () {
      final c = [_c(now, mood: 8), _c(now, mood: 6), _c(now.subtract(const Duration(days: 2)), mood: 4)];
      expect(ProgressMath.dailyMood(c, days: 3, now: now), [4, 0, 7]);
    });

    test('phaseIndex walks through phases by elapsed weeks', () {
      final start = now.subtract(const Duration(days: 22)); // week 3
      expect(ProgressMath.phaseIndex(start, [2, 2, 4], now: now), 1);
      expect(ProgressMath.phaseIndex(now.subtract(const Duration(days: 400)), [2, 2], now: now), 1);
    });
  });

  group('OnboardingProfile', () {
    test('severity grows with hours, breadth and triggers', () {
      const light = OnboardingProfile(dailyHours: 1, habits: ['Gaming']);
      const heavy = OnboardingProfile(
        dailyHours: 12,
        habits: ['a', 'b', 'c', 'd', 'e'],
        triggers: ['1', '2', '3', '4', '5', '6'],
      );
      expect(light.severityBand, 'mild');
      expect(heavy.severity, 100);
      expect(heavy.severityBand, 'high');
    });

    test('round-trips through a map', () {
      const p = OnboardingProfile(displayName: 'Sam', habits: ['Gaming'], dailyHours: 5.5, coachStyle: 'motivator');
      final back = OnboardingProfile.fromMap(p.toMap());
      expect(back.displayName, 'Sam');
      expect(back.habits, ['Gaming']);
      expect(back.dailyHours, 5.5);
      expect(back.coachStyle, 'motivator');
    });
  });

  group('Entitlement', () {
    final future = Timestamp.fromDate(DateTime.now().add(const Duration(days: 3)));
    final past = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)));

    test('trial grants premium access to all books', () {
      final e = Entitlement.fromMap({'trialEndsAt': future});
      expect(e.inTrial, isTrue);
      expect(e.canAccess('any'), isTrue);
      expect(e.trialDaysLeft, inInclusiveRange(3, 4));
    });

    test('expired trial only keeps owned books', () {
      final e = Entitlement.fromMap({
        'trialEndsAt': past,
        'ownedBooks': ['b1'],
      });
      expect(e.hasPremium, isFalse);
      expect(e.canAccess('b1'), isTrue);
      expect(e.canAccess('b2'), isFalse);
    });
  });

  test('FormTemplate parses AI-generated JSON', () {
    final f = FormTemplate.fromMap({
      'id': 'urge_log',
      'title': 'Urge log',
      'description': 'd',
      'icon': 'breath',
      'accent': 'ember',
      'frequency': 'on_urge',
      'fields': [
        {'id': 'intensity', 'label': 'How strong?', 'type': 'scale', 'min': 0, 'max': 10},
        {'id': 'what', 'label': 'What happened?', 'type': 'unknown_type'},
      ],
    });
    expect(f.fields.first.type, FieldType.scale);
    expect(f.fields.last.type, FieldType.text, reason: 'unknown types degrade to text');
  });

  group('Content encryption', () {
    // Produced by functions/scripts/encrypt-book.ts with a key of 32 × 0x07.
    final blob = base64Decode('FOtiVUB9HQvRJWKbl/p2P6U4psolHbWlsoQg6H6wZKGiE7FfT2dIqgW+D+pcCts1VKZb2dAEa4dDC89Z');
    final key = List.filled(32, 7);

    test('decrypts files encrypted by the publishing script', () async {
      final clear = await LibraryRepository.decryptBlob(blob, key);
      expect(utf8.decode(clear), '%PDF-1.7 Overcome protected book');
    });

    test('rejects tampered content', () async {
      final tampered = Uint8List.fromList(blob)..[20] ^= 1;
      expect(() => LibraryRepository.decryptBlob(tampered, key), throwsA(anything));
    });

    test('rejects the wrong key', () async {
      expect(() => LibraryRepository.decryptBlob(blob, List.filled(32, 8)), throwsA(anything));
    });
  });

  testWidgets('Book3D renders every face orientation without errors', (tester) async {
    for (final angle in [0.0, -0.4, math.pi / 2, math.pi, -math.pi / 2, 3.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Book3D(book: _book, angle: angle),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('RingGauge and CategoryBars animate to their values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RingGauge(progress: 0.5, center: Text('50')),
              CategoryBars(values: {'Gaming': 3, 'Social': 6}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('50'), findsOneWidget);
    expect(find.text('Gaming'), findsOneWidget);
  });
}
