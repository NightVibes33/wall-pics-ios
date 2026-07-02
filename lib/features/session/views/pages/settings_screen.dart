import 'dart:async';
import 'dart:io';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/auth/apple_auth.dart';
import 'package:Prism/auth/google_auth.dart';
import 'package:Prism/core/account/delete_account_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/constants/app_constants.dart';
import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/persistence/data_sources/cache_maintenance_service.dart';
import 'package:Prism/core/persistence/data_sources/favorites_local_data_source.dart';
import 'package:Prism/core/persistence/data_sources/notifications_local_data_source.dart';
import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/core/persistence/persistence_keys.dart';
import 'package:Prism/core/platform/pigeon/prism_media_api.g.dart';
import 'package:Prism/core/purchases/paywall_orchestrator.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/core/purchases/subscription_tier.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/state/auth_runtime.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/core/utils/url_launcher_compat.dart' as launcher_compat;
import 'package:Prism/env/env.dart';
import 'package:Prism/features/navigation/views/widgets/personalized_feed_settings_bottom_sheet.dart';
import 'package:Prism/core/widgets/home/core/headingChipBar.dart';
import 'package:Prism/features/onboarding_v2/src/common/onboarding_v2_keys.dart';
import 'package:Prism/features/favourite_walls/views/favourite_walls_bloc_adapter.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/main.dart' as main;
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:animations/animations.dart';
import 'package:auto_route/auto_route.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mailer/flutter_mailer.dart';
import 'package:fluttertoast/fluttertoast.dart';

@RoutePage()
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final CacheMaintenanceService _cacheMaintenance = getIt<CacheMaintenanceService>();
  final SettingsLocalDataSource _settingsLocal = getIt<SettingsLocalDataSource>();
  final FavoritesLocalDataSource _favoritesLocal = getIt<FavoritesLocalDataSource>();
  final NotificationsLocalDataSource _notificationsLocal = getIt<NotificationsLocalDataSource>();

  late bool _notifWotd;
  late bool _notifPromo;
  late String _downloadQuality;
  late String _feedMix;
  late List<String> _selectedInterests;

  bool _loadingStorage = true;
  bool _authBusy = false;
  int _downloadCount = 0;
  int _favoriteWallCount = 0;
  int _favoriteSetupCount = 0;
  int _notificationCount = 0;
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _notifWotd = _settingsLocal.get<bool>(PersistenceKeys.notifWotd, defaultValue: true);
    _notifPromo = _settingsLocal.get<bool>(PersistenceKeys.notifPromo, defaultValue: true);
    _downloadQuality = _normalizedDownloadQuality(
      _settingsLocal.get<String>(PersistenceKeys.downloadQuality, defaultValue: 'original'),
    );
    _feedMix = _normalizedFeedMix(_settingsLocal.get<String>(personalizedFeedMixLocalKey, defaultValue: 'balanced'));
    _selectedInterests = _readSelectedInterests();
    unawaited(_reloadStorageStats());
  }

  String get _userScope => app_state.prismUser.id.trim();

  int get _selectedInterestCount => _selectedInterests.length;

  bool get _isSignedIn => app_state.prismUser.loggedIn;

  SubscriptionTier get _subscriptionTier => SubscriptionTier.fromValue(app_state.prismUser.subscriptionTier);

  String get _subscriptionLabel {
    return switch (_subscriptionTier) {
      SubscriptionTier.free => 'Free plan',
      SubscriptionTier.pro => 'Prism Pro',
      SubscriptionTier.lifetime => 'Lifetime access',
    };
  }

  String get _entitlementLabel {
    return switch (_subscriptionTier) {
      SubscriptionTier.free => 'No premium entitlement',
      SubscriptionTier.pro => 'Recurring premium access active',
      SubscriptionTier.lifetime => 'Permanent premium access active',
    };
  }

  String get _downloadAccessLabel {
    if (_subscriptionTier.isPaid || app_state.prismUser.premium) {
      return 'Unlimited downloads';
    }
    final int limit = app_state.prismUser.freeDownloadsLimit > 0 ? app_state.prismUser.freeDownloadsLimit : 3;
    final int used = app_state.prismUser.freeDownloadsToday < 0 ? 0 : app_state.prismUser.freeDownloadsToday;
    final int remaining = limit - used < 0 ? 0 : limit - used;
    return '$remaining of $limit free downloads left today';
  }

  String get _planUnlocksLabel {
    return switch (_subscriptionTier) {
      SubscriptionTier.free => '3 free downloads per day',
      SubscriptionTier.pro => 'Infinite downloads',
      SubscriptionTier.lifetime => 'Infinite downloads',
    };
  }

  String get _authProviderLabel {
    final provider = app_state.prismUser.authProvider.trim().toLowerCase();
    switch (provider) {
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      default:
        return _isSignedIn ? 'Connected account' : 'Not signed in';
    }
  }

  String get _privacySummary {
    if (_isSignedIn) {
      return 'Account profile, favorites, download quota and feed preferences are tied to this account. Downloads and caches remain on this device until removed.';
    }
    return 'You are in local-only mode. Downloads, caches and settings stay on this device until you sign in or clear them.';
  }

  String _normalizedDownloadQuality(String raw) {
    final value = raw.trim().toLowerCase();
    return value == 'compressed' ? 'compressed' : 'original';
  }

  String _normalizedFeedMix(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'catalog' || value == 'balanced') {
      return value;
    }
    return 'balanced';
  }

  List<String> _readSelectedInterests() {
    final raw = _settingsLocal.get<String>(OnboardingV2Keys.selectedInterests, defaultValue: '');
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _reloadStorageStats() async {
    int downloads = _downloadCount;
    try {
      final result = await PrismMediaHostApi().listDownloads();
      if (result.success) {
        downloads = result.items.length;
      }
    } catch (error, stackTrace) {
      logger.w('Failed to load download stats.', error: error, stackTrace: stackTrace);
    }

    final wallScope = _userScope;
    final wallCount = _favoritesLocal.wallFavouriteCount(wallScope);
    final setupCount = _favoritesLocal.setupFavouriteCount(wallScope);
    int totalNotifications = _notificationCount;
    int unreadNotifications = _unreadNotificationCount;
    try {
      final items = await _notificationsLocal.readAll();
      totalNotifications = items.length;
      unreadNotifications = items.where((item) => !item.read).length;
    } catch (error, stackTrace) {
      logger.w('Failed to load notification stats.', error: error, stackTrace: stackTrace);
    }
    if (!mounted) return;
    setState(() {
      _downloadCount = downloads;
      _favoriteWallCount = wallCount;
      _favoriteSetupCount = setupCount;
      _notificationCount = totalNotifications;
      _unreadNotificationCount = unreadNotifications;
      _loadingStorage = false;
    });
  }

  void _trackSettingsAction(AnalyticsActionValue action) {
    unawaited(
      analytics.track(
        SettingsActionTappedEvent(
          action: action,
          isSignedIn: app_state.prismUser.loggedIn,
          sourceContext: 'settings_screen',
        ),
      ),
    );
  }

  void _trackSettingsAuthResult({
    required AnalyticsActionValue action,
    required EventResultValue result,
    AnalyticsReasonValue? reason,
  }) {
    unawaited(analytics.track(SettingsAuthActionResultEvent(action: action, result: result, reason: reason)));
  }

  Color get _accentColor {
    final c = Theme.of(context).colorScheme.error;
    return c == Colors.black ? Colors.grey : c;
  }

  TextStyle get _titleStyle => TextStyle(
    color: Theme.of(context).colorScheme.secondary,
    fontWeight: FontWeight.w600,
    fontFamily: 'Proxima Nova',
  );

  static const TextStyle _subtitleStyle = TextStyle(fontSize: 12);

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        color: Theme.of(context).cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: _accentColor,
                  fontFamily: 'Proxima Nova',
                ),
              ),
            ),
            ...children,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _settingsHeader() {
    final user = app_state.prismUser;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String tier = _subscriptionLabel;
    final String syncState = _isSignedIn ? 'Cloud sync enabled' : 'Local-only mode';
    final String headline = _isSignedIn ? (user.name.trim().isEmpty ? 'Your account' : user.name.trim()) : 'Settings';
    final String subhead = _isSignedIn ? (user.email.trim().isEmpty ? syncState : user.email.trim()) : 'Control app behavior, storage and account access';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: <Color>[
              cs.surfaceContainerHighest.withValues(alpha: 0.92),
              cs.surfaceContainerHigh.withValues(alpha: 0.96),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: user.profilePhoto.trim().isNotEmpty ? NetworkImage(user.profilePhoto.trim()) : null,
                    child: user.profilePhoto.trim().isEmpty ? const Icon(Icons.person_outline) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(headline, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle.copyWith(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(subhead, maxLines: 2, overflow: TextOverflow.ellipsis, style: _subtitleStyle.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _StatPill(label: tier, icon: user.premium ? Icons.workspace_premium_outlined : Icons.lock_open_outlined),
                  _StatPill(label: syncState, icon: _isSignedIn ? Icons.cloud_done_outlined : Icons.phone_iphone_outlined),
                  _StatPill(label: _entitlementLabel, icon: user.premium ? Icons.verified_outlined : Icons.lock_outline),
                  _StatPill(label: '${user.followers.length} followers', icon: Icons.people_outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountSection() {
    if (!_isSignedIn) {
      return _sectionCard(
        title: 'ACCOUNT',
        children: <Widget>[
          ListTile(
            leading: const Icon(JamIcons.log_in),
            title: Text('Sign in with Google', style: _titleStyle),
            subtitle: const Text('Enable cloud sync for favorites, profile and notifications', style: _subtitleStyle),
            trailing: _authBusy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: _authBusy ? null : () => _signInWithGoogle(),
          ),
          if (!Env.sideloadBuild)
            ListTile(
              leading: const Icon(Icons.apple),
              title: Text('Sign in with Apple', style: _titleStyle),
              subtitle: const Text('Use your Apple account for Prism access', style: _subtitleStyle),
              trailing: _authBusy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: _authBusy ? null : () => _signInWithApple(),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('What account access enables', style: _titleStyle),
            subtitle: const Text('Sync preferences and unlock 3 free downloads per day after sign-in.', style: _subtitleStyle),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text('Connected provider', style: _titleStyle),
            subtitle: const Text('Sign in with Google or Apple to link this device to a Prism account.', style: _subtitleStyle),
          ),
        ],
      );
    }

    final user = app_state.prismUser;
    final syncLabel = user.email.trim().isEmpty ? 'Signed in' : user.email.trim();
    final bool isPaid = _subscriptionTier.isPaid || user.premium;
    return _sectionCard(
      title: 'ACCOUNT',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text('Plan', style: _titleStyle),
          subtitle: Text('$_subscriptionLabel • $syncLabel', style: _subtitleStyle),
        ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text('Connected provider', style: _titleStyle),
          subtitle: Text(_authProviderLabel, style: _subtitleStyle),
        ),
        ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text('Plan benefits', style: _titleStyle),
          subtitle: Text(
            _subscriptionTier.isPaid
                ? 'Infinite downloads with premium access and paid-tier content unlocks.'
                : '3 free downloads per day. Upgrade for infinite downloads and premium access.',
            style: _subtitleStyle,
          ),
        ),
        ListTile(
          leading: Icon(isPaid ? Icons.workspace_premium_outlined : Icons.lock_outline),
          title: Text('Entitlement status', style: _titleStyle),
          subtitle: Text(_entitlementLabel, style: _subtitleStyle),
        ),
        ListTile(
          leading: Icon(isPaid ? JamIcons.infinite : Icons.download_outlined),
          title: Text('Download access', style: _titleStyle),
          subtitle: Text('$_planUnlocksLabel • $_downloadAccessLabel', style: _subtitleStyle),
        ),
        if (!isPaid)
          ListTile(
            leading: const Icon(Icons.upgrade_outlined),
            title: Text('Upgrade to Prism Pro', style: _titleStyle),
            subtitle: const Text('Unlock premium wallpapers, premium setup access and Pro-only perks', style: _subtitleStyle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => PaywallOrchestrator.instance.present(
              context,
              placement: PaywallPlacement.mainUpsell,
              source: 'settings_account_upgrade',
            ),
          ),
        if (isPaid)
          ListTile(
            leading: const Icon(Icons.open_in_new_outlined),
            title: Text('Manage subscription', style: _titleStyle),
            subtitle: const Text('Open Apple subscription settings for renewals and cancellations', style: _subtitleStyle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openManageSubscription,
          ),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: Text('Restore purchases', style: _titleStyle),
          subtitle: const Text('Restore Prism Pro access from this Apple account', style: _subtitleStyle),
          onTap: _restorePurchases,
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: Text('Sync mode', style: _titleStyle),
          subtitle: const Text('Favorites, profile and feed preferences are tied to this account', style: _subtitleStyle),
        ),
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: Text('Profile data', style: _titleStyle),
          subtitle: Text(
            '${user.following.length} following • ${user.followers.length} followers • ${user.badges.length} badges • ${user.subPrisms.length} subscriptions',
            style: _subtitleStyle,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: Text('Account activity', style: _titleStyle),
          subtitle: Text(
            '${user.transactions.length} account records • ${user.uploadsThisWeek} uploads this week',
            style: _subtitleStyle,
          ),
        ),
        ListTile(
          leading: Icon(JamIcons.log_out, color: _accentColor),
          title: Text('Sign out', style: _titleStyle.copyWith(color: _accentColor)),
          subtitle: const Text('Keep app data on this device, disconnect cloud access', style: _subtitleStyle),
          onTap: _authBusy ? null : _signOut,
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_rounded, color: Colors.red[400]),
          title: Text('Delete account', style: _titleStyle.copyWith(color: Colors.red[400])),
          subtitle: const Text('Permanently delete your Prism account and remote data', style: _subtitleStyle),
          onTap: _showDeleteAccountDialog,
        ),
      ],
    );
  }

  Widget _personalizationSection() {
    final String mixLabel = switch (_feedMix) {
      'catalog' => 'Catalog-first',
      _ => 'Balanced',
    };
    final String interestsLabel = _selectedInterestCount == 0
        ? 'No interests selected yet'
        : '$_selectedInterestCount interests selected';
    return _sectionCard(
      title: 'PERSONALIZATION',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.tune_outlined),
          title: Text('Feed preferences', style: _titleStyle),
          subtitle: Text('$interestsLabel • $mixLabel mix', style: _subtitleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openFeedPreferences,
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt_outlined),
          title: Text('Reset feed personalization', style: _titleStyle),
          subtitle: const Text('Clear selected interests and revert to the default feed mix', style: _subtitleStyle),
          onTap: _resetFeedPersonalization,
        ),
      ],
    );
  }

  Widget _downloadsSection() {
    final String qualityLabel = _downloadQuality == 'compressed' ? 'Faster, smaller files' : 'Original resolution';
    return _sectionCard(
      title: 'DOWNLOADS',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.high_quality_outlined),
          title: Text('Download quality', style: _titleStyle),
          subtitle: Text(qualityLabel, style: _subtitleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _showDownloadQualitySheet,
        ),
      ],
    );
  }

  Widget _notificationsSection() {
    return _sectionCard(
      title: 'NOTIFICATIONS',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text('Notification delivery', style: _titleStyle),
          subtitle: Text(
            _isSignedIn
                ? 'This build uses in-app and local alerts. Remote topic subscriptions are not active here.'
                : 'Available as local preferences now. Sign in if you want them tied to your account later.',
            style: _subtitleStyle,
          ),
        ),
        SwitchListTile(
          activeThumbColor: _accentColor,
          secondary: const Icon(Icons.wb_sunny_outlined),
          value: _notifWotd,
          title: Text('Wall of the Day', style: _titleStyle),
          subtitle: const Text('Daily wallpaper recommendation alert', style: _subtitleStyle),
          onChanged: (value) async {
            setState(() => _notifWotd = value);
            await _settingsLocal.set(PersistenceKeys.notifWotd, value);
          },
        ),
        SwitchListTile(
          activeThumbColor: _accentColor,
          secondary: const Icon(Icons.campaign_outlined),
          value: _notifPromo,
          title: Text('Promotional alerts', style: _titleStyle),
          subtitle: const Text('New features, events and release announcements', style: _subtitleStyle),
          onChanged: (value) async {
            setState(() => _notifPromo = value);
            await _settingsLocal.set(PersistenceKeys.notifPromo, value);
          },
        ),
      ],
    );
  }

  Widget _notificationInboxSection() {
    final String subtitle = _notificationCount == 0
        ? 'No saved notifications on this device'
        : '$_unreadNotificationCount unread • $_notificationCount total saved notifications';
    return _sectionCard(
      title: 'NOTIFICATION INBOX',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.inbox_outlined),
          title: Text('Notification inbox', style: _titleStyle),
          subtitle: Text(subtitle, style: _subtitleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.push(const NotificationRoute()),
        ),
        ListTile(
          leading: const Icon(Icons.mark_email_read_outlined),
          title: Text('Mark all as read', style: _titleStyle),
          subtitle: const Text('Keep notifications but clear the unread count', style: _subtitleStyle),
          onTap: _markAllNotificationsRead,
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: Text('Clear notification inbox', style: _titleStyle),
          subtitle: const Text('Delete saved in-app notifications from this device', style: _subtitleStyle),
          onTap: _clearNotificationInbox,
        ),
      ],
    );
  }

  Widget _storageSection() {
    final String subtitle = _loadingStorage
        ? 'Loading device usage…'
        : '$_downloadCount downloads • $_favoriteWallCount favorite walls • $_favoriteSetupCount favorite setups';
    return _sectionCard(
      title: 'STORAGE',
      children: <Widget>[
        ListTile(
          leading: const Icon(JamIcons.pie_chart_alt),
          title: Text('Device data summary', style: _titleStyle),
          subtitle: Text(subtitle, style: _subtitleStyle),
          trailing: _loadingStorage ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text('Clear cache', style: _titleStyle),
          subtitle: const Text('Remove cached images, feed cache and notification cache', style: _subtitleStyle),
          onTap: () async {
            _trackSettingsAction(AnalyticsActionValue.clearCacheTapped);
            await _cacheMaintenance.clearTransientCache();
            if (!mounted) return;
            toasts.codeSend('Cleared cache.');
            unawaited(_reloadStorageStats());
          },
        ),
        ListTile(
          leading: const Icon(JamIcons.trash_alt),
          title: Text('Clear downloads', style: _titleStyle),
          subtitle: const Text('Remove downloaded wallpapers from device storage', style: _subtitleStyle),
          onTap: _showClearDownloadsDialog,
        ),
        ListTile(
          leading: const Icon(JamIcons.heart),
          title: Text('Clear favorites', style: _titleStyle),
          subtitle: const Text('Remove locally saved favorite walls and setups', style: _subtitleStyle),
          onTap: _showClearFavoritesDialog,
        ),
      ],
    );
  }

  Widget _privacySection() {
    return _sectionCard(
      title: 'PRIVACY & DATA',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text('Data overview', style: _titleStyle),
          subtitle: Text(_privacySummary, style: _subtitleStyle),
        ),
        ListTile(
          leading: const Icon(Icons.download_done_outlined),
          title: Text('Stored on this device', style: _titleStyle),
          subtitle: Text('$_downloadCount downloads • cache files • $_notificationCount saved notifications', style: _subtitleStyle),
        ),
        if (_isSignedIn)
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text('Stored with your account', style: _titleStyle),
            subtitle: Text('Favorites, account profile, subscription tier and daily download quota state', style: _subtitleStyle),
          ),
      ],
    );
  }

  Widget _supportSection() {
    return _sectionCard(
      title: 'SUPPORT',
      children: <Widget>[
        ListTile(
          leading: const Icon(JamIcons.info),
          title: Text('About Prism', style: _titleStyle),
          subtitle: Text('Version ${app_state.currentAppVersion} (${app_state.currentAppVersionCode})', style: _subtitleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.push(const AboutRoute()),
        ),
        ListTile(
          leading: const Icon(JamIcons.bug),
          title: Text('Report a bug', style: _titleStyle),
          subtitle: const Text('Open an email draft with device info and logs attached', style: _subtitleStyle),
          onTap: _sendBugReport,
        ),
        ListTile(
          leading: const Icon(JamIcons.refresh),
          title: Text('Restart app', style: _titleStyle),
          subtitle: const Text('Restart the app after account or storage changes', style: _subtitleStyle),
          onTap: () {
            _trackSettingsAction(AnalyticsActionValue.restartAppTapped);
            main.RestartWidget.restartApp(context);
          },
        ),
      ],
    );
  }

  Widget _adminSection() {
    if (!app_state.isAdminUser()) return const SizedBox.shrink();
    return _sectionCard(
      title: 'ADMIN',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text('Debug panel', style: _titleStyle),
          subtitle: const Text('Logs, network, tools and storage inspector', style: _subtitleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.pushPath('/debug-panel'),
        ),
        ListTile(
          leading: const Icon(JamIcons.file),
          title: Text('Remote Store telemetry', style: _titleStyle),
          subtitle: const Text('Database usage and telemetry stats', style: _subtitleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.push(const RemoteStoreTelemetryRoute()),
        ),
      ],
    );
  }

  Future<void> _openFeedPreferences() async {
    await openPersonalizedFeedSettingsBottomSheet(
      context,
      onPreferencesSaved: () {
        if (!mounted) return;
        setState(() {
          _feedMix = _normalizedFeedMix(_settingsLocal.get<String>(personalizedFeedMixLocalKey, defaultValue: 'balanced'));
          _selectedInterests = _readSelectedInterests();
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _feedMix = _normalizedFeedMix(_settingsLocal.get<String>(personalizedFeedMixLocalKey, defaultValue: 'balanced'));
      _selectedInterests = _readSelectedInterests();
    });
  }

  Future<void> _resetFeedPersonalization() async {
    await _settingsLocal.set(OnboardingV2Keys.selectedInterests, '');
    await _settingsLocal.set(personalizedFeedMixLocalKey, 'balanced');
    if (!mounted) return;
    setState(() {
      _feedMix = 'balanced';
      _selectedInterests = const <String>[];
    });
    toasts.codeSend('Feed preferences reset.');
  }

  Future<void> _showDownloadQualitySheet() async {
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text('Download quality', style: _titleStyle),
                subtitle: const Text('Choose how wallpaper downloads are saved', style: _subtitleStyle),
              ),
              RadioListTile<String>(
                value: 'original',
                groupValue: _downloadQuality,
                activeColor: _accentColor,
                title: const Text('Original resolution'),
                subtitle: const Text('Best quality, larger downloads'),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
              RadioListTile<String>(
                value: 'compressed',
                groupValue: _downloadQuality,
                activeColor: _accentColor,
                title: const Text('Compressed'),
                subtitle: const Text('Smaller files, faster saves'),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    final normalized = _normalizedDownloadQuality(selected);
    await _settingsLocal.set(PersistenceKeys.downloadQuality, normalized);
    if (!mounted) return;
    setState(() => _downloadQuality = normalized);
  }

  Future<void> _signInWithGoogle() async {
    await _runAuthAction(
      action: AnalyticsActionValue.signInTapped,
      runner: () => app_state.gAuth.signInWithGoogle(),
      isCancelled: (result) => result == GoogleAuth.signInCancelledResult,
    );
  }

  Future<void> _signInWithApple() async {
    await _runAuthAction(
      action: AnalyticsActionValue.signInTapped,
      runner: () => globalAppleAuth.signInWithApple(),
      isCancelled: (result) => result == AppleAuth.signInCancelledResult,
    );
  }

  Future<void> _runAuthAction({
    required AnalyticsActionValue action,
    required Future<String> Function() runner,
    required bool Function(String result) isCancelled,
  }) async {
    if (_authBusy) return;
    _trackSettingsAction(action);
    setState(() => _authBusy = true);
    try {
      final result = await runner();
      if (!mounted) return;
      if (isCancelled(result)) {
        _trackSettingsAuthResult(
          action: action,
          result: EventResultValue.cancelled,
          reason: AnalyticsReasonValue.userCancelled,
        );
        toasts.codeSend('Sign in cancelled.');
        return;
      }
      _trackSettingsAuthResult(action: action, result: EventResultValue.success);
      toasts.codeSend('Login successful.');
      main.RestartWidget.restartApp(context);
    } catch (error, stackTrace) {
      logger.e('Sign in failed from settings.', error: error, stackTrace: stackTrace);
      _trackSettingsAuthResult(
        action: action,
        result: EventResultValue.failure,
        reason: AnalyticsReasonValue.error,
      );
      if (mounted) {
        toasts.error('Something went wrong, please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    _trackSettingsAction(AnalyticsActionValue.restorePurchaseTapped);
    final restored = await PurchasesService.instance.restore(source: 'settings_account_restore');
    if (!mounted) return;
    if (restored) {
      toasts.codeSend('Purchases restored.');
      main.RestartWidget.restartApp(context);
      return;
    }
    toasts.error(PurchasesService.instance.availabilityMessage ?? 'No active Pro purchase found.');
  }

  Future<void> _openManageSubscription() async {
    const uri = 'https://apps.apple.com/account/subscriptions';
    final opened = await launcher_compat.launch(uri);
    if (!mounted) return;
    if (!opened) {
      toasts.error('Unable to open Apple subscription settings.');
    }
  }

  Future<void> _signOut() async {
    _trackSettingsAction(AnalyticsActionValue.logoutTapped);
    setState(() => _authBusy = true);
    try {
      final bool signedOut = await app_state.gAuth.signOutGoogle();
      _trackSettingsAuthResult(
        action: AnalyticsActionValue.logoutTapped,
        result: signedOut ? EventResultValue.success : EventResultValue.failure,
        reason: signedOut ? null : AnalyticsReasonValue.error,
      );
      if (!signedOut) {
        toasts.error('Something went wrong, please try again.');
        return;
      }
      if (!mounted) return;
      toasts.codeSend('Signed out.');
      main.RestartWidget.restartApp(context);
    } catch (error, stackTrace) {
      logger.e('Sign out failed from settings.', error: error, stackTrace: stackTrace);
      _trackSettingsAuthResult(
        action: AnalyticsActionValue.logoutTapped,
        result: EventResultValue.failure,
        reason: AnalyticsReasonValue.error,
      );
      if (mounted) {
        toasts.error('Something went wrong, please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  void _showClearDownloadsDialog() {
    showModal(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        content: const SizedBox(
          height: 50,
          width: 250,
          child: Center(child: Text('Do you want to remove all your downloads?')),
        ),
        actions: <Widget>[
          MaterialButton(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              bool deleted = false;
              try {
                final result = await PrismMediaHostApi().clearDownloads();
                deleted = result.success;
              } catch (error, stackTrace) {
                logger.e('Failed to clear downloads.', error: error, stackTrace: stackTrace);
              }
              if (!mounted) return;
              Fluttertoast.showToast(
                msg: deleted ? 'Deleted all downloads.' : 'No downloads found.',
                toastLength: Toast.LENGTH_LONG,
                textColor: Colors.white,
                backgroundColor: deleted ? Colors.green[400] : Colors.red[400],
              );
              unawaited(_reloadStorageStats());
            },
            child: Text('YES', style: TextStyle(fontSize: 16.0, color: _accentColor)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: MaterialButton(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              color: _accentColor,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('NO', style: TextStyle(fontSize: 16.0, color: Colors.white)),
            ),
          ),
        ],
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  void _showClearFavoritesDialog() {
    showModal(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        content: const SizedBox(
          height: 60,
          width: 250,
          child: Center(child: Text('Do you want to remove all your favorite walls and setups?')),
        ),
        actions: <Widget>[
          MaterialButton(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final scope = _userScope;
              await _favoritesLocal.clearWallFavourites(scope);
              await _favoritesLocal.clearSetupFavourites(scope);
              if (mounted) {
                context.favouriteWallsAdapter(listen: false).deleteData();
                toasts.codeSend('Cleared favorites.');
              }
              unawaited(_reloadStorageStats());
            },
            child: Text('YES', style: TextStyle(fontSize: 16.0, color: _accentColor)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: MaterialButton(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              color: _accentColor,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('NO', style: TextStyle(fontSize: 16.0, color: Colors.white)),
            ),
          ),
        ],
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showModal(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        title: Text('Delete Account', style: _titleStyle.copyWith(color: Colors.red[400])),
        content: const SizedBox(
          width: 250,
          child: Text(
            'This will permanently delete your account data, remove cloud access and sign you out. This action cannot be undone.',
          ),
        ),
        actions: <Widget>[
          MaterialButton(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            color: Colors.red[400],
            onPressed: () async {
              Navigator.of(ctx).pop();
              final loaderDialog = Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).primaryColor,
                  ),
                  width: MediaQuery.of(context).size.width * .7,
                  height: MediaQuery.of(context).size.height * .3,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Deleting account...'),
                      ],
                    ),
                  ),
                ),
              );
              showDialog(barrierDismissible: false, context: context, builder: (_) => loaderDialog);
              try {
                await DeleteAccountService.instance.deleteAccount();
                if (!mounted) return;
                Navigator.pop(context);
                main.RestartWidget.restartApp(context);
              } catch (error, stackTrace) {
                if (!mounted) return;
                Navigator.pop(context);
                logger.e('Delete account failed.', error: error, stackTrace: stackTrace);
                final String message = error.toString().contains('requires-recent-login')
                    ? 'Please sign out and sign in again, then try deleting your account.'
                    : 'Something went wrong, please try again.';
                toasts.error(message);
              }
            },
            child: const Text('DELETE', style: TextStyle(fontSize: 16.0, color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: MaterialButton(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('CANCEL', style: TextStyle(fontSize: 16.0, color: _accentColor)),
            ),
          ),
        ],
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Future<void> _markAllNotificationsRead() async {
    final items = await _notificationsLocal.readAll();
    if (items.isEmpty) {
      toasts.codeSend('No notifications to update.');
      return;
    }
    await _notificationsLocal.writeAll(items.map((item) => item.copyWith(read: true)).toList(growable: false));
    if (!mounted) return;
    toasts.codeSend('Marked all notifications as read.');
    unawaited(_reloadStorageStats());
  }

  Future<void> _clearNotificationInbox() async {
    await _notificationsLocal.clearAll();
    await _notificationsLocal.clearLastFetchAtUtc();
    if (!mounted) return;
    toasts.codeSend('Cleared notification inbox.');
    unawaited(_reloadStorageStats());
  }

  Future<void> _sendBugReport() async {
    final deviceBody = await _bugReportDeviceBody();
    final String zipPath = await zipLogs();
    if (zipPath.startsWith(logExportDisabledMarker)) {
      toasts.error('Log export is temporarily disabled.');
      return;
    }
    final parts = zipPath.split('::::');
    final encryptedZipKey = parts.length > 1 ? parts.first : 'logs';
    final encryptedZipPath = parts.length > 1 ? parts.last : zipPath;
    final mailOptions = MailOptions(
      body: '$deviceBody<br><br>Enter the bug/issue below -<br><br>',
      subject: '[BUG REPORT::PRISM] - $encryptedZipKey',
      recipients: <String>['nightvibes33@users.noreply.github.com'],
      isHTML: true,
      attachments: <String>[encryptedZipPath],
    );
    await FlutterMailer.send(mailOptions);
    toasts.codeSend('Bug report opened.');
  }

  Future<String> _bugReportDeviceBody() async {
    try {
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return '----x-x-x----<br>Device info -<br><br>iOS ${info.systemVersion}<br>Device: ${info.utsname.machine}<br>Name: ${info.name}<br>----x-x-x----';
      }
    } catch (_) {}
    return '----x-x-x----<br>Device info unavailable<br>----x-x-x----';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      appBar: const PreferredSize(
        preferredSize: Size(double.infinity, 55),
        child: HeadingChipBar(current: 'Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: <Widget>[
          _settingsHeader(),
          _accountSection(),
          _personalizationSection(),
          _downloadsSection(),
          _notificationsSection(),
          _notificationInboxSection(),
          _storageSection(),
          _privacySection(),
          _adminSection(),
          _supportSection(),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.surface.withValues(alpha: 0.7),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
