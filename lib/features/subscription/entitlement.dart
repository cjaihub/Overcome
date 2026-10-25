import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';

/// Server-owned access state (`users/{uid}.entitlement`). Clients can read
/// it but never write it — see firestore.rules.
class Entitlement {
  const Entitlement({this.trialEndsAt, this.premiumUntil, this.plan, this.ownedBooks = const {}});

  final DateTime? trialEndsAt;
  final DateTime? premiumUntil;
  final String? plan;
  final Set<String> ownedBooks;

  bool get inTrial => trialEndsAt != null && trialEndsAt!.isAfter(DateTime.now());
  bool get isSubscribed => premiumUntil != null && premiumUntil!.isAfter(DateTime.now());
  bool get hasPremium => inTrial || isSubscribed;

  int get trialDaysLeft => inTrial ? trialEndsAt!.difference(DateTime.now()).inHours ~/ 24 + 1 : 0;

  bool canAccess(String bookId) => hasPremium || ownedBooks.contains(bookId);

  String get label => isSubscribed
      ? 'Premium${plan == null ? '' : ' · $plan'}'
      : inTrial
      ? 'Free trial · $trialDaysLeft day${trialDaysLeft == 1 ? '' : 's'} left'
      : 'Free';

  factory Entitlement.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const Entitlement();
    DateTime? ts(String k) => (m[k] as Timestamp?)?.toDate();
    return Entitlement(
      trialEndsAt: ts('trialEndsAt'),
      premiumUntil: ts('premiumUntil'),
      plan: m['plan'] as String?,
      ownedBooks: {...?(m['ownedBooks'] as List?)?.cast<String>()},
    );
  }
}

final entitlementProvider = Provider<Entitlement>((ref) {
  final doc = ref.watch(userDocProvider).value;
  return Entitlement.fromMap(doc?['entitlement'] as Map<String, dynamic>?);
});
