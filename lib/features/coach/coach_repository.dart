import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/analytics_service.dart';
import '../../core/services/firebase_providers.dart';
import 'voice_engine.dart';

class CoachAction {
  const CoachAction({required this.type, required this.label, required this.target});

  /// `route` (in-app screen) or `url` (opens in an in-app browser tab).
  final String type;
  final String label;
  final String target;

  factory CoachAction.fromMap(Map<String, dynamic> m) =>
      CoachAction(type: m['type'] as String, label: m['label'] as String, target: m['target'] as String);
}

class Emotion {
  const Emotion({required this.label, required this.confidence, this.cues = ''});
  final String label;
  final double confidence;
  final String cues;

  factory Emotion.fromMap(Map<String, dynamic> m) => Emotion(
    label: m['label'] as String? ?? 'neutral',
    confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
    cues: m['cues'] as String? ?? '',
  );
}

class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.imageUrl,
    this.emotion,
    this.actions = const [],
    this.voiceRate,
    this.voicePitch,
    this.viaVoice = false,
  });

  final String id;
  final String role;
  final String text;
  final DateTime at;
  final String? imageUrl;
  final Emotion? emotion;
  final List<CoachAction> actions;
  final double? voiceRate;
  final double? voicePitch;
  final bool viaVoice;

  bool get isUser => role == 'user';

  factory CoachMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    final style = m['voiceStyle'] as Map<String, dynamic>?;
    return CoachMessage(
      id: d.id,
      role: m['role'] as String,
      text: m['text'] as String? ?? '',
      at: (m['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrl: m['imageUrl'] as String?,
      emotion: m['emotion'] == null ? null : Emotion.fromMap(Map<String, dynamic>.from(m['emotion'] as Map)),
      actions: [
        for (final a in (m['actions'] as List? ?? const [])) CoachAction.fromMap(Map<String, dynamic>.from(a as Map)),
      ],
      voiceRate: (style?['rate'] as num?)?.toDouble(),
      voicePitch: (style?['pitch'] as num?)?.toDouble(),
      viaVoice: m['voice'] != null,
    );
  }
}

/// Chat with the AI coach. The callable writes both the user's message and
/// the reply, so the conversation history can't be forged from the client.
class CoachRepository {
  CoachRepository(this._db, this._auth, this._storage, this._functions, this._analytics);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final AnalyticsService _analytics;

  String get _uid => _auth.currentUser!.uid;

  Stream<List<CoachMessage>> watch({int limit = 80}) => _db
      .collection('users/$_uid/coach')
      .orderBy('clientAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(CoachMessage.fromDoc).toList());

  Future<void> send({required String text, Uint8List? image, VoiceSample? voice, String assistantName = 'Ova'}) async {
    String? imagePath;
    if (image != null) {
      imagePath = 'users/$_uid/chat/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _storage.ref(imagePath).putData(image, SettableMetadata(contentType: 'image/jpeg'));
    }
    await _functions
        .httpsCallable('coachReply', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
        .call<Map<String, dynamic>>({
          'text': text,
          'imagePath': ?imagePath,
          'voice': ?voice?.toMap(),
          'assistantName': assistantName,
          'localTime': DateTime.now().toIso8601String(),
        });
    await _analytics.log(voice != null ? AppEvent.voiceCheckIn : AppEvent.coachMessage, {'image': image != null});
  }
}

final coachRepositoryProvider = Provider<CoachRepository>(
  (ref) => CoachRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(storageProvider),
    ref.watch(functionsProvider),
    ref.watch(analyticsProvider),
  ),
);

final coachMessagesProvider = StreamProvider.autoDispose<List<CoachMessage>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(coachRepositoryProvider).watch();
});
