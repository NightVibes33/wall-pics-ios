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
  static const int _defaultFreeDownloadLimit = 3;

  Future<bool> ensureCanStartDownload(
    BuildContext context, {
    String? sourceContext,
    bool isPremiumContent = false,
  }) async {
    await PurchasesService.instance.checkAndPersistPremium();
    if (app_state.prismUser.premium) {
      return true;
    }

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
      if (quota == null) {
        if (_localRemainingFreeDownloads() > 0) {
          return true;
        }
        if (context.mounted) {
          await PaywallOrchestrator.instance.present(
            context,
            placement: PaywallPlacement.freeDownloadLimit,
            source: sourceContext ?? 'download_limit_local',
          );
        }
        return app_state.prismUser.premium;
      }
      if (quota.isPremium || quota.remaining > 0) {
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
    } catch (error, stackTrace) {
      logger.w(
        'Remote download quota check failed; using local quota fallback.',
        tag: 'DownloadQuota',
        error: error,
        stackTrace: stackTrace,
      );
      if (_localRemainingFreeDownloads() > 0) {
        return true;
      }
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
    } catch (error, stackTrace) {
      logger.w(
        'Remote download quota claim failed; using local quota fallback.',
        tag: 'DownloadQuota',
        error: error,
        stackTrace: stackTrace,
      );
      return _claimLocalFreeDownload();
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
      return false;
    }
    final claimed = await claimSuccessfulFreeDownload(contentId: contentId, sourceContext: sourceContext);
    if (claimed) {
      return true;
    }
    if (_localRemainingFreeDownloads() > 0) {
      final localClaimed = await _claimLocalFreeDownload();
      if (localClaimed) {
        return true;
      }
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

  int _freeDownloadLimit() {
    final limit = app_state.prismUser.freeDownloadsLimit;
    return limit > 0 ? limit : _defaultFreeDownloadLimit;
  }

  String _todayUtc() => DateTime.now().toUtc().toIso8601String().split('T').first;

  bool _normalizeLocalQuota() {
    final today = _todayUtc();
    var changed = false;
    if (app_state.prismUser.freeDownloadDay != today) {
      app_state.prismUser.freeDownloadDay = today;
      app_state.prismUser.freeDownloadsToday = 0;
      changed = true;
    }
    if (app_state.prismUser.freeDownloadsLimit <= 0) {
      app_state.prismUser.freeDownloadsLimit = _defaultFreeDownloadLimit;
      changed = true;
    }
    return changed;
  }

  int _localRemainingFreeDownloads() {
    _normalizeLocalQuota();
    final remaining = _freeDownloadLimit() - app_state.prismUser.freeDownloadsToday;
    return remaining > 0 ? remaining : 0;
  }

  Future<bool> _claimLocalFreeDownload() async {
    _normalizeLocalQuota();
    final limit = _freeDownloadLimit();
    if (app_state.prismUser.freeDownloadsToday >= limit) {
      toasts.error('Free download limit reached for today.');
      await app_state.persistPrismUser();
      return false;
    }

    app_state.prismUser.freeDownloadsToday += 1;
    await app_state.persistPrismUser();

    final remaining = limit - app_state.prismUser.freeDownloadsToday;
    if (remaining > 0) {
      toasts.codeSend('$remaining free downloads left today.');
    }
    return true;
  }
}
