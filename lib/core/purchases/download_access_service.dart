import 'package:Prism/auth/github_user_store.dart';
import 'package:Prism/core/purchases/paywall_orchestrator.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:flutter/widgets.dart';

class DownloadAccessService {
  DownloadAccessService._();

  static final DownloadAccessService instance = DownloadAccessService._();

  final GitHubUserStore _userStore = const GitHubUserStore();

  Future<bool> ensureCanStartDownload(
    BuildContext context, {
    String? sourceContext,
    bool isPremiumContent = false,
  }) async {
    await PurchasesService.instance.checkAndPersistPremium();
    if (app_state.prismUser.premium) return true;
    if (isPremiumContent) {
      if (context.mounted) {
        await PaywallOrchestrator.instance.present(
          context,
          placement: PaywallPlacement.premiumWallpaperDownload,
          source: sourceContext ?? 'premium_wallpaper_download',
        );
      }
      return app_state.prismUser.premium;
    }
    if (!app_state.prismUser.loggedIn || app_state.prismUser.id.trim().isEmpty) {
      toasts.error('Sign in to download wallpapers.');
      return false;
    }
    try {
      final quota = await _userStore.getDownloadQuota();
      return quota != null && (quota.isPremium || quota.remaining > 0);
    } catch (error, stackTrace) {
      logger.w('Authoritative download quota check failed.', tag: 'DownloadQuota', error: error, stackTrace: stackTrace);
      toasts.error('Unable to verify download access. Try again.');
      return false;
    }
  }

  Future<bool> claimSuccessfulFreeDownload({String? contentId, String? sourceContext}) async {
    await PurchasesService.instance.checkAndPersistPremium();
    if (app_state.prismUser.premium) return true;
    if (!app_state.prismUser.loggedIn || app_state.prismUser.id.trim().isEmpty) return false;
    try {
      final claim = await _userStore.claimFreeDownload(contentId: contentId, sourceContext: sourceContext);
      if (!claim.allowed) {
        toasts.error('Free download limit reached for today.');
      } else if (claim.quota.remaining > 0) {
        toasts.codeSend('${claim.quota.remaining} free downloads left today.');
      }
      return claim.allowed;
    } catch (error, stackTrace) {
      logger.w('Authoritative download claim failed.', tag: 'DownloadQuota', error: error, stackTrace: stackTrace);
      toasts.error('Unable to verify download access. Try again.');
      return false;
    }
  }

  Future<bool> ensureCanDownload(
    BuildContext context, {
    String? contentId,
    String? sourceContext,
    bool isPremiumContent = false,
  }) async {
    final canStart = await ensureCanStartDownload(
      context,
      sourceContext: sourceContext,
      isPremiumContent: isPremiumContent,
    );
    if (!canStart) {
      if (context.mounted && app_state.prismUser.loggedIn) {
        await PaywallOrchestrator.instance.present(
          context,
          placement: PaywallPlacement.freeDownloadLimit,
          source: sourceContext ?? 'download_limit',
        );
      }
      return app_state.prismUser.premium;
    }
    return claimSuccessfulFreeDownload(contentId: contentId, sourceContext: sourceContext);
  }
}
