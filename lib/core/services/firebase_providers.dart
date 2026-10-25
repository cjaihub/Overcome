import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);
final functionsProvider = Provider<FirebaseFunctions>((_) => FirebaseFunctions.instance);
final storageProvider = Provider<FirebaseStorage>((_) => FirebaseStorage.instance);

final authStateProvider = StreamProvider<User?>((ref) => ref.watch(firebaseAuthProvider).idTokenChanges());

/// Custom claims (e.g. `admin: true`) set by the `setAdmin` function.
final claimsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const {};
  final token = await user.getIdTokenResult();
  return token.claims ?? const {};
});

final isAdminProvider = Provider<bool>((ref) => ref.watch(claimsProvider).value?['admin'] == true);

/// Live `users/{uid}` document: profile, entitlement, aggregated stats.
final userDocProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(firestoreProvider).doc('users/${user.uid}').snapshots().map((s) => s.data());
});
