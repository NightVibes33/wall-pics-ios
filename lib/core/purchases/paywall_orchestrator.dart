import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/purchases/purchase_constants.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/core/purchases/widgets/prism_pro_paywall.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:flutter/widgets.dart';

class PaywallPlacement {
  const PaywallPlacement._();

  static const String mainUpsell = 'main_upsell';
  static const String lowBalance = 'low_balance';
  static const String afterAdWatch3 = 'after_ad_watch_3';
  static const String blockedSetupCreate = 'blocked_setup_create';
  static const String uploadLimitReached = 'upload_limit_reached';
  static const String onboardingCompletion = 'onboarding_completion';
  static const String freeDownloadLimit = 'free_download_limit';
}

class PaywallOrchestrator {
  PaywallOrchestrator._();

  static final PaywallOrchestrator instance = PaywallOrchestrator._();

  static const int _adWatchThreshold = 3;
  int _adWatchCount = 0;
  bool _adWatchPrompted = false;

  Future<bool> present(BuildContext context, {required String placement, required String source}) async {
    final String normalizedPlacement = placement.trim().isEmpty ? PaywallPlacement.mainUpsell : placement.trim();
    _logPlacementTriggerContext(placement: normalizedPlacement, source: source);
    analytics.track(
      PaywallImpressionEvent(source: source, placement: normalizedPlacement, rcOrFallback: RcOrFallbackValue.fallback),
    );

    final bool unlocked = await showPrismProPaywall(context, placement: normalizedPlacement, source: source);
    final bool isPremium = await PurchasesService.instance.checkAndPersistPremium(
      conversionContext: SubscriptionConversionContext(
        source: source,
        packageType: normalizedPlacement,
        subscriptionTier: app_state.prismUser.subscriptionTier,
      ),
    );
    if (unlocked || isPremium) {
      _resetAdWatchCounter();
    }
    analytics.track(
      PaywallResultEvent(
        source: source,
        placement: normalizedPlacement,
        result: unlocked || isPremium ? PaywallResultValue.purchased : PaywallResultValue.cancelled,
        entitlementSynced: isPremium ? 1 : 0,
        entitlement: PurchaseConstants.entitlementV3ProAccess,
        rcOrFallback: RcOrFallbackValue.fallback,
      ),
    );
    return unlocked || isPremium;
  }

  Future<void> recordRewardedAdWatchAndMaybeUpsell(BuildContext context, {required String source}) async {
    if (app_state.prismUser.premium) {
      _resetAdWatchCounter();
      return;
    }

    _adWatchCount += 1;
    if (_adWatchCount < _adWatchThreshold || _adWatchPrompted) {
      return;
    }
    _adWatchPrompted = true;
    await present(context, placement: PaywallPlacement.afterAdWatch3, source: source);
  }

  void _resetAdWatchCounter() {
    _adWatchCount = 0;
    _adWatchPrompted = false;
  }

  void _logPlacementTriggerContext({required String placement, required String source}) {
    switch (placement) {
      case PaywallPlacement.lowBalance:
        analytics.track(SubscriptionTriggerLowBalanceEvent(source: source, placement: placement));
        return;
      case PaywallPlacement.afterAdWatch3:
        analytics.track(SubscriptionTriggerAfterAdWatch3Event(source: source, placement: placement));
        return;
      case PaywallPlacement.blockedSetupCreate:
        analytics.track(SubscriptionTriggerSetupCreateBlockEvent(source: source, placement: placement));
        return;
      case PaywallPlacement.uploadLimitReached:
        analytics.track(SubscriptionTriggerUploadLimitBlockEvent(source: source, placement: placement));
        return;
      default:
        return;
    }
  }
}
