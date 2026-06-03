import 'package:Prism/auth/github_user_store.dart';
import 'package:Prism/core/purchases/paywall_orchestrator.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:flutter/widgets.dart';

class DownloadAccessService {
  DownloadAccessService._();

  static final DownloadAccessService instance = DownloadAccessService._();

  final GitHubUserStore _userStore = const GitHubUserStore();

  Future<bool> ensureCanStartDownload(
    BuildContext context, {
    String? sourceContext,
  }) async {
    await PurchasesService.instance.checkAndPersistPremium();
    if (app_state.prismUser.premium) {
      return true;
    }

    if (!app_state.prismUser.loggedIn || app_state.prismUser.id.trim().isEmpty) {
      toasts.error('Sign in to download wallpapers.');
      return false;
    }

    try {
      final quota = await _userStore.getDownloadQuota();
      if (quota == null || quota.isPremium || quota.remaining > 0) {
        return true;
      }
      if (context.mounted) {
        await PaywallOrchestrator.instance.present(
          context,
          placement: PaywallPlacement.freeDownloadLimit,
          source: sourceContext ?? 'download_limit',
        );
      }
      return app_state.prismUser.premium;
    } catch (_) {
      toasts.error('Could not verify download limit. Sign in again or unlock Pro.');
      if (context.mounted) {
        await PaywallOrchestrator.instance.present(
          context,
          placement: PaywallPlacement.freeDownloadLimit,
          source: sourceContext ?? 'download_limit_error',
        );
      }
      return app_state.prismUser.premium;
    }
  }

  Future<bool> claimSuccessfulFreeDownload({
    String? contentId,
    String? sourceContext,
  }) async {
    await PurchasesService.instance.checkAndPersistPremium();
    if (app_state.prismUser.premium) {
      return true;
    }
    if (!app_state.prismUser.loggedIn || app_state.prismUser.id.trim().isEmpty) {
      return false;
    }

    try {
      final claim = await _userStore.claimFreeDownload(contentId: contentId, sourceContext: sourceContext);
      if (!claim.allowed) {
        toasts.error('Free download limit reached for today.');
        return false;
      }
      if (claim.quota.remaining > 0) {
        toasts.codeSend('${claim.quota.remaining} free downloads left today.');
      }
      return true;
    } catch (_) {
      toasts.error('Could not update download quota. Sign in again or unlock Pro.');
      return false;
    }
  }

  Future<bool> ensureCanDownload(
    BuildContext context, {
    String? contentId,
    String? sourceContext,
  }) async {
    final canStart = await ensureCanStartDownload(context, sourceContext: sourceContext);
    if (!canStart) {
      return false;
    }
    final claimed = await claimSuccessfulFreeDownload(contentId: contentId, sourceContext: sourceContext);
    if (claimed) {
      return true;
    }
    if (context.mounted) {
      await PaywallOrchestrator.instance.present(
        context,
        placement: PaywallPlacement.freeDownloadLimit,
        source: sourceContext ?? 'download_claim_denied',
      );
    }
    return app_state.prismUser.premium;
  }
}
