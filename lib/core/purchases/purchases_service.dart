import 'dart:async';
import 'dart:io';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/auth/github_user_store.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/purchases/purchase_constants.dart';
import 'package:Prism/core/purchases/subscription_tier.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/env/env.dart';
import 'package:Prism/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionConversionContext {
  const SubscriptionConversionContext({
    required this.source,
    this.productId,
    this.packageType,
    this.subscriptionTier,
    this.price,
    this.currency,
  });

  final String source;
  final String? productId;
  final String? packageType;
  final String? subscriptionTier;
  final num? price;
  final String? currency;
}

/// Direct Apple StoreKit purchase service.
///
/// App Store Connect products are queried with Flutter's official
/// `in_app_purchase` plugin, payment is handled
/// by Apple, and successful transactions are mirrored into the private user
/// store so the rest of the app can use `app_state.prismUser.premium`.
class PurchasesService {
  PurchasesService._();

  static final PurchasesService instance = PurchasesService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final GitHubUserStore _userStore = const GitHubUserStore();
  final Map<String, ProductDetails> _productsById = <String, ProductDetails>{};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Completer<bool>? _pendingPurchaseCompleter;
  bool _configured = false;
  bool _available = false;

  Future<void> configureEarly() => ensureConfigured(app_state.prismUser.id);

  Future<void> ensureConfigured(String userId) async {
    if (_configured) {
      return;
    }
    _configured = true;
    if (Env.sideloadBuild || !Platform.isIOS) {
      _available = false;
      return;
    }
    _available = await _iap.isAvailable();
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        logger.e('Apple purchase stream failed', error: error, stackTrace: stackTrace);
        _completePendingPurchase(false);
      },
    );
  }

  bool get isAvailable => _available;

  Future<List<ProductDetails>> loadProducts({bool refresh = false}) async {
    await ensureConfigured(app_state.prismUser.id);
    if (!_available) {
      return const <ProductDetails>[];
    }
    if (!refresh && _productsById.isNotEmpty) {
      return _sortedProducts(_productsById.values.toList(growable: false));
    }

    final response = await _iap.queryProductDetails(PurchaseConstants.appleProductIds.toSet());
    if (response.error != null) {
      logger.w('Apple product query failed: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      logger.w('Apple products missing in App Store Connect: ${response.notFoundIDs.join(', ')}');
    }
    _productsById
      ..clear()
      ..addEntries(response.productDetails.map((product) => MapEntry(product.id, product)));
    return _sortedProducts(response.productDetails);
  }

  Future<bool> purchaseProduct(String productId, {required String source}) async {
    await ensureConfigured(app_state.prismUser.id);
    if (!_available) {
      return false;
    }
    final product = await _productById(productId);
    if (product == null) {
      return false;
    }

    _pendingPurchaseCompleter = Completer<bool>();
    final purchaseParam = PurchaseParam(productDetails: product);
    final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started) {
      _completePendingPurchase(false);
      return false;
    }
    return _pendingPurchaseCompleter!.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => app_state.prismUser.premium,
    );
  }

  Future<bool> restore({required String source}) async {
    await ensureConfigured(app_state.prismUser.id);
    if (!_available) {
      return false;
    }
    _pendingPurchaseCompleter = Completer<bool>();
    await _iap.restorePurchases();
    return _pendingPurchaseCompleter!.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => app_state.prismUser.premium,
    );
  }

  Future<bool> checkAndPersistPremium({SubscriptionConversionContext? conversionContext}) async {
    await ensureConfigured(app_state.prismUser.id);
    await _syncAnalyticsSubscriptionState(
      isPremium: app_state.prismUser.premium,
      tier: SubscriptionTier.fromValue(app_state.prismUser.subscriptionTier),
    );
    return app_state.prismUser.premium;
  }

  Future<ProductDetails?> _productById(String productId) async {
    if (_productsById.containsKey(productId)) {
      return _productsById[productId];
    }
    await loadProducts(refresh: true);
    return _productsById[productId];
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    var grantedAccess = false;
    for (final purchase in purchases) {
      if (!PurchaseConstants.appleProductIds.contains(purchase.productID)) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _persistPaidPurchase(purchase);
          grantedAccess = true;
          break;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          logger.w('Apple purchase did not complete: ${purchase.error}');
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    if (grantedAccess) {
      _completePendingPurchase(true);
    } else if (purchases.any((purchase) => purchase.status == PurchaseStatus.error || purchase.status == PurchaseStatus.canceled)) {
      _completePendingPurchase(false);
    }
  }

  Future<void> _persistPaidPurchase(PurchaseDetails purchase) async {
    final tier = _tierForProduct(purchase.productID);
    final product = _productsById[purchase.productID];
    final wasPremium = app_state.prismUser.premium;

    app_state.prismUser.premium = true;
    app_state.prismUser.subscriptionTier = tier.value;
    await app_state.persistPrismUser();

    await _userStore.syncAppleSubscription(
      productId: purchase.productID,
      purchaseId: purchase.purchaseID ?? '',
      transactionId: purchase.purchaseID ?? '',
      verificationData: purchase.verificationData.serverVerificationData,
      status: purchase.status.name,
    );
    await _syncAnalyticsSubscriptionState(isPremium: true, tier: tier);
    if (!wasPremium) {
      await _logSubscriptionConversion(
        tier: tier,
        conversionContext: SubscriptionConversionContext(
          source: 'apple_storekit',
          productId: purchase.productID,
          packageType: _packageTypeForProduct(purchase.productID),
          subscriptionTier: tier.value,
          price: product?.rawPrice,
          currency: product?.currencyCode,
        ),
      );
    }

    analytics.track(
      SubscriptionEntitlementRefreshEvent(
        result: SubscriptionEntitlementRefreshResultValue.success,
        subscriptionTier: tier.value,
        isPremium: 1,
        activeEntitlements: PurchaseConstants.entitlementV3ProAccess,
      ),
    );
  }

  Future<void> _syncAnalyticsSubscriptionState({required bool isPremium, required SubscriptionTier tier}) async {
    await analytics.setUserProperty(name: AnalyticsUserProperty.subscriptionTier.wireName, value: tier.value);
    await analytics.setUserProperty(name: AnalyticsUserProperty.isPremium.wireName, value: isPremium ? '1' : '0');
  }

  Future<void> _logSubscriptionConversion({
    required SubscriptionTier tier,
    SubscriptionConversionContext? conversionContext,
  }) async {
    final context = conversionContext ?? SubscriptionConversionContext(source: 'apple_storekit', subscriptionTier: tier.value);
    await analytics.track(
      SubscriptionConversionEvent(
        source: context.source,
        productId: context.productId ?? 'unknown_product',
        packageType: context.packageType ?? 'unknown_package',
        subscriptionTier: context.subscriptionTier ?? tier.value,
        price: context.price ?? 0,
        currency: context.currency ?? 'unknown_currency',
      ),
    );
    final price = context.price ?? 0;
    if (price > 0) {
      unawaited(analytics.track(RevenueRecordedEvent(amountUsd: price.toDouble(), source: 'apple_storekit')));
    }
  }

  void _completePendingPurchase(bool value) {
    final completer = _pendingPurchaseCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
    }
    _pendingPurchaseCompleter = null;
  }

  Future<void> logOut() async {
    _completePendingPurchase(false);
  }

  SubscriptionTier _tierForProduct(String productId) {
    return productId == PurchaseConstants.productLifetime ? SubscriptionTier.lifetime : SubscriptionTier.pro;
  }

  String _packageTypeForProduct(String productId) {
    switch (productId) {
      case PurchaseConstants.productMonthly:
        return 'monthly';
      case PurchaseConstants.productYearly:
        return 'yearly';
      case PurchaseConstants.productLifetime:
        return 'lifetime';
      default:
        return 'unknown_package';
    }
  }

  List<ProductDetails> _sortedProducts(List<ProductDetails> products) {
    final order = <String, int>{
      PurchaseConstants.productYearly: 0,
      PurchaseConstants.productMonthly: 1,
      PurchaseConstants.productLifetime: 2,
    };
    return products.toList(growable: false)..sort((a, b) => (order[a.id] ?? 99).compareTo(order[b.id] ?? 99));
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _configured = false;
    _available = false;
    _productsById.clear();
  }
}
