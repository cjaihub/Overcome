import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/services/analytics_service.dart';
import '../../core/services/firebase_providers.dart';

abstract final class Products {
  static const monthly = 'overcome_premium_monthly';
  static const yearly = 'overcome_premium_yearly';
  static const subscriptions = {monthly, yearly};
}

/// Store purchases → server-side receipt verification → entitlement.
/// The app never grants access itself; `verifyPurchase` validates the token
/// with Google Play / the App Store and writes `users/{uid}.entitlement`.
class SubscriptionRepository {
  SubscriptionRepository(this._functions, this._analytics);

  final FirebaseFunctions _functions;
  final AnalyticsService _analytics;
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _status = StreamController<String>.broadcast();

  /// Human-readable purchase status for the paywall.
  Stream<String> get status => _status.stream;

  void start() {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => _status.add('Purchase failed: $e'));
  }

  Future<List<ProductDetails>> products({String? bookProductId}) async {
    if (!await _iap.isAvailable()) return const [];
    final ids = {...Products.subscriptions, ?bookProductId};
    final res = await _iap.queryProductDetails(ids);
    return res.productDetails;
  }

  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    // Subscriptions and books are both non-consumables from the store's view.
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _status.add('Processing…');
        case PurchaseStatus.error:
          _status.add(p.error?.message ?? 'Purchase failed');
        case PurchaseStatus.canceled:
          _status.add('Purchase cancelled');
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _functions.httpsCallable('verifyPurchase').call<void>({
              'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
              'productId': p.productID,
              'token': p.verificationData.serverVerificationData,
            });
            _status.add('success');
            _analytics.log(AppEvent.purchase, {'productId': p.productID});
          } on FirebaseFunctionsException catch (e) {
            _status.add(e.message ?? 'Could not verify purchase');
          }
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  void dispose() {
    _sub?.cancel();
    _status.close();
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  final repo = SubscriptionRepository(ref.watch(functionsProvider), ref.watch(analyticsProvider))..start();
  ref.onDispose(repo.dispose);
  return repo;
});
