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

  Future<bool> ensureCanDownload(
    BuildContext context, {
    String? contentId,
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
      final claim = await _userStore.claimFreeDownload(contentId: contentId, sourceContext: sourceContext);
      if (claim.allowed) {
        if (claim.quota.remaining > 0) {
          toasts.codeSend('${claim.quota.remaining} free downloads left today.');
        }
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
}
