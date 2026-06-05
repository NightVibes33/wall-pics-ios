import 'dart:async';

import 'package:Prism/auth/github_user_store.dart';
import 'package:Prism/core/purchases/paywall_orchestrator.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    if (await _localRemainingFreeDownloads() > 0) {
      return true;
    }

    try {
      final quota = await _userStore.getDownloadQuota();
      if (quota != null && (quota.isPremium || quota.remaining > 0)) {
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
      if (await _localRemainingFreeDownloads() > 0) {
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

    final claimed = await _claimLocalFreeDownload();
    if (!claimed) {
      return false;
    }
    unawaited(_syncRemoteFreeDownloadClaim(contentId: contentId, sourceContext: sourceContext));
    return true;
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
    if (await _localRemainingFreeDownloads() > 0) {
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

  Future<void> _syncRemoteFreeDownloadClaim({
    String? contentId,
    String? sourceContext,
  }) async {
    final localDay = app_state.prismUser.freeDownloadDay;
    final localToday = app_state.prismUser.freeDownloadsToday;
    final localLimit = _freeDownloadLimit();
    try {
      final claim = await _userStore.claimFreeDownload(contentId: contentId, sourceContext: sourceContext);
      app_state.prismUser.freeDownloadDay = localDay;
      app_state.prismUser.freeDownloadsToday = localToday;
      app_state.prismUser.freeDownloadsLimit = localLimit;
      await app_state.persistPrismUser();
      if (!claim.allowed) {
        logger.w(
          'Remote download quota claim was denied after local free allowance succeeded; preserving local quota.',
          tag: 'DownloadQuota',
        );
      }
    } catch (error, stackTrace) {
      logger.w(
        'Remote download quota claim failed after local free allowance succeeded.',
        tag: 'DownloadQuota',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  int _freeDownloadLimit() {
    final limit = app_state.prismUser.freeDownloadsLimit;
    return limit > 0 ? limit : _defaultFreeDownloadLimit;
  }

  String _todayUtc() => DateTime.now().toUtc().toIso8601String().split('T').first;

  String _quotaPrefsPrefix() {
    final userId = app_state.prismUser.id.trim();
    return 'prism_local_download_quota_${userId.isEmpty ? 'anonymous' : userId}';
  }

  Future<_LocalDownloadQuota> _readLocalQuota() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _quotaPrefsPrefix();
    final today = _todayUtc();
    final limit = _freeDownloadLimit();
    var day = prefs.getString('$prefix.day') ?? '';
    var used = prefs.getInt('$prefix.used') ?? 0;
    var storedLimit = prefs.getInt('$prefix.limit') ?? limit;
    if (storedLimit <= 0) {
      storedLimit = _defaultFreeDownloadLimit;
    }
    if (day != today) {
      day = today;
      used = 0;
    }
    if (used < 0) {
      used = 0;
    }
    if (used > storedLimit) {
      used = storedLimit;
    }
    final quota = _LocalDownloadQuota(day: day, used: used, limit: storedLimit);
    await _writeLocalQuota(prefs, prefix, quota);
    return quota;
  }

  Future<void> _writeLocalQuota(SharedPreferences prefs, String prefix, _LocalDownloadQuota quota) async {
    await prefs.setString('$prefix.day', quota.day);
    await prefs.setInt('$prefix.used', quota.used);
    await prefs.setInt('$prefix.limit', quota.limit);
    app_state.prismUser.freeDownloadDay = quota.day;
    app_state.prismUser.freeDownloadsToday = quota.used;
    app_state.prismUser.freeDownloadsLimit = quota.limit;
    await app_state.persistPrismUser();
  }

  Future<int> _localRemainingFreeDownloads() async {
    final quota = await _readLocalQuota();
    return quota.remaining;
  }

  Future<bool> _claimLocalFreeDownload() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _quotaPrefsPrefix();
    final quota = await _readLocalQuota();
    if (quota.used >= quota.limit) {
      toasts.error('Free download limit reached for today.');
      await _writeLocalQuota(prefs, prefix, quota);
      return false;
    }

    final updated = _LocalDownloadQuota(day: quota.day, used: quota.used + 1, limit: quota.limit);
    await _writeLocalQuota(prefs, prefix, updated);

    if (updated.remaining > 0) {
      toasts.codeSend('${updated.remaining} free downloads left today.');
    }
    return true;
  }
}

class _LocalDownloadQuota {
  const _LocalDownloadQuota({required this.day, required this.used, required this.limit});

  final String day;
  final int used;
  final int limit;

  int get remaining {
    final value = limit - used;
    return value > 0 ? value : 0;
  }
}
