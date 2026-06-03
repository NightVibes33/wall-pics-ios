/// Centralized Apple StoreKit identifiers for Prism Pro.
///
/// Create matching products in App Store Connect for the `Přism` app:
/// - `prism_pro_monthly` as an auto-renewable monthly subscription.
/// - `prism_pro_yearly` as an auto-renewable yearly subscription.
/// - `prism_pro_lifetime` as a non-consumable one-time purchase.
class PurchaseConstants {
  PurchaseConstants._();

  static const String entitlementV3ProAccess = 'prism_pro_access';

  static const String productMonthly = 'prism_pro_monthly';
  static const String productYearly = 'prism_pro_yearly';
  static const String productLifetime = 'prism_pro_lifetime';

  static const List<String> appleProductIds = <String>[
    productMonthly,
    productYearly,
    productLifetime,
  ];

  static const String privacyPolicyUrl = 'https://github.com/NightVibes33/prism-ios/blob/main/PRIVACY.md';
  static const String termsOfUseUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
}
