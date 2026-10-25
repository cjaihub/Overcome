import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';

sealed class PhoneVerification {}

class CodeSent extends PhoneVerification {
  CodeSent(this.verificationId, this.resendToken);
  final String verificationId;
  final int? resendToken;
}

class AutoVerified extends PhoneVerification {}

class AuthRepository {
  AuthRepository(this._auth, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  User? get currentUser => _auth.currentUser;

  /// Sends a one-time SMS code to [phone] (E.164). On Android the code may
  /// be auto-retrieved, in which case the user is signed in immediately.
  Future<PhoneVerification> sendCode(String phone, {int? resendToken}) {
    final result = Completer<PhoneVerification>();
    _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        await _auth.signInWithCredential(credential);
        await bootstrap();
        if (!result.isCompleted) result.complete(AutoVerified());
      },
      verificationFailed: (e) {
        if (!result.isCompleted) result.completeError(_friendly(e));
      },
      codeSent: (id, token) {
        if (!result.isCompleted) result.complete(CodeSent(id, token));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return result.future;
  }

  Future<void> confirmCode(String verificationId, String smsCode) async {
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode);
      await _auth.signInWithCredential(credential);
      await bootstrap();
    } on FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  /// Idempotent server-side setup: creates the user document and grants the
  /// one-time 7-day trial (one per phone number, enforced server side).
  Future<void> bootstrap() async {
    await _functions.httpsCallable('bootstrapUser').call<void>();
    await _auth.currentUser?.getIdToken(true);
  }

  /// Redeems a one-time unlock code (e.g. printed inside a purchased book).
  Future<String> redeemCode(String code) async {
    try {
      final res = await _functions.httpsCallable('redeemAccessCode').call<Map<String, dynamic>>({'code': code.trim()});
      return res.data['message'] as String? ?? 'Code redeemed';
    } on FirebaseFunctionsException catch (e) {
      throw e.message ?? 'That code could not be redeemed.';
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> deleteAccount() async {
    await _functions.httpsCallable('deleteAccount').call<void>();
    await _auth.signOut();
  }

  String _friendly(FirebaseAuthException e) => switch (e.code) {
    'invalid-phone-number' => 'That phone number doesn\'t look right.',
    'invalid-verification-code' => 'The code is incorrect. Please try again.',
    'session-expired' => 'The code expired. Request a new one.',
    'too-many-requests' => 'Too many attempts. Please wait a moment.',
    _ => e.message ?? 'Something went wrong. Please try again.',
  };
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(functionsProvider)),
);
