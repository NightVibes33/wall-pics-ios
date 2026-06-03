import 'package:Prism/core/purchases/purchase_constants.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

Future<bool> showPrismProPaywall(BuildContext context, {required String placement, required String source}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PrismProPaywall(placement: placement, source: source),
  );
  return result == true;
}

class PrismProPaywall extends StatefulWidget {
  const PrismProPaywall({required this.placement, required this.source, super.key});

  final String placement;
  final String source;

  @override
  State<PrismProPaywall> createState() => _PrismProPaywallState();
}

class _PrismProPaywallState extends State<PrismProPaywall> {
  late Future<List<ProductDetails>> _productsFuture;
  String? _loadingProductId;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = PurchasesService.instance.loadProducts(refresh: true);
  }

  Future<void> _purchase(String productId) async {
    if (_loadingProductId != null || _restoring) {
      return;
    }
    setState(() => _loadingProductId = productId);
    try {
      final purchased = await PurchasesService.instance.purchaseProduct(productId, source: widget.source);
      if (!mounted) return;
      if (purchased) {
        toasts.codeSend('Přism Pro unlocked.');
        Navigator.of(context).pop(true);
      } else {
        toasts.error('Purchase was not completed.');
      }
    } catch (_) {
      if (mounted) {
        toasts.error('Apple purchase failed. Please retry.');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingProductId = null);
      }
    }
  }

  Future<void> _restore() async {
    if (_loadingProductId != null || _restoring) {
      return;
    }
    setState(() => _restoring = true);
    try {
      final restored = await PurchasesService.instance.restore(source: widget.source);
      if (!mounted) return;
      if (restored) {
        toasts.codeSend('Purchases restored.');
        Navigator.of(context).pop(true);
      } else {
        toasts.error('No active Pro purchase found.');
      }
    } catch (_) {
      if (mounted) {
        toasts.error('Restore failed. Please retry.');
      }
    } finally {
      if (mounted) {
        setState(() => _restoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF08080A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, -8))],
      ),
      child: FutureBuilder<List<ProductDetails>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          final products = snapshot.data ?? const <ProductDetails>[];
          final loading = snapshot.connectionState == ConnectionState.waiting;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(JamIcons.crown_f, color: Color(0xFF3DA7FF), size: 30),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Přism Pro',
                      style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 31, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontFamily: 'Satoshi', fontSize: 16, height: 1.28),
              ),
              const SizedBox(height: 16),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 34),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                )
              else if (products.isEmpty)
                _UnavailableProducts(onRetry: () => setState(() => _productsFuture = PurchasesService.instance.loadProducts(refresh: true)))
              else
                ...products.map(_productRow),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _restoring ? null : _restore,
                child: _restoring
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Restore purchases', style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontWeight: FontWeight.w700)),
              ),
              Text(
                'Payments are processed by Apple. Subscriptions renew automatically until canceled in Apple account settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.44), fontFamily: 'Satoshi', fontSize: 11, height: 1.25),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _productRow(ProductDetails product) {
    final isYearly = product.id == PurchaseConstants.productYearly;
    final isLoading = _loadingProductId == product.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isYearly ? const Color(0xFF0B84FF) : const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isLoading ? null : () => _purchase(product.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            _titleForProduct(product.id),
                            style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 19, fontWeight: FontWeight.w900),
                          ),
                          if (isYearly) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                              child: const Text(
                                'BEST',
                                style: TextStyle(color: Color(0xFF0B84FF), fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitleForProduct(product.id),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isLoading)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                else
                  Text(
                    product.price,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 18, fontWeight: FontWeight.w900),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _titleForProduct(String productId) {
    switch (productId) {
      case PurchaseConstants.productYearly:
        return 'Yearly Pro';
      case PurchaseConstants.productMonthly:
        return 'Monthly Pro';
      case PurchaseConstants.productLifetime:
        return 'Lifetime Pro';
      default:
        return 'Přism Pro';
    }
  }

  String _subtitleForProduct(String productId) {
    switch (productId) {
      case PurchaseConstants.productYearly:
        return 'Best value for unlimited downloads';
      case PurchaseConstants.productMonthly:
        return 'Flexible monthly access';
      case PurchaseConstants.productLifetime:
        return 'Pay once, keep Pro forever';
      default:
        return 'Unlock the full catalog';
    }
  }
}

class _UnavailableProducts extends StatelessWidget {
  const _UnavailableProducts({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF18181C), borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: <Widget>[
          const Text(
            'Apple products are not available yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Create prism_pro_monthly, prism_pro_yearly, and prism_pro_lifetime in App Store Connect, then retry.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontFamily: 'Satoshi', fontSize: 13, height: 1.28),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
