import 'dart:async';
import 'dart:io';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/auth/google_auth.dart';
import 'package:Prism/core/account/delete_account_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/persistence/data_sources/cache_maintenance_service.dart';
import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/core/persistence/persistence_keys.dart';
import 'package:Prism/core/platform/pigeon/prism_media_api.g.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/core/widgets/home/core/headingChipBar.dart';
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
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final CacheMaintenanceService _cacheMaintenance = getIt<CacheMaintenanceService>();
  final SettingsLocalDataSource _settingsLocal = getIt<SettingsLocalDataSource>();

  late bool _notifWotd;
  late bool _notifPromo;

  @override
  void initState() {
    super.initState();
    _notifWotd = _settingsLocal.get<bool>(PersistenceKeys.notifWotd, defaultValue: true);
    _notifPromo = _settingsLocal.get<bool>(PersistenceKeys.notifPromo, defaultValue: true);
    final savedDownloadQuality = _settingsLocal.get<String>(PersistenceKeys.downloadQuality, defaultValue: 'original');
    if (savedDownloadQuality != 'original') {
      _settingsLocal.set(PersistenceKeys.downloadQuality, 'original');
    }
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

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Color get _accentColor {
    final c = Theme.of(context).colorScheme.error;
    return c == Colors.black ? Colors.grey : c;
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        color: Theme.of(context).cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
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

  TextStyle get _titleStyle => TextStyle(
    color: Theme.of(context).colorScheme.secondary,
    fontWeight: FontWeight.w500,
    fontFamily: 'Proxima Nova',
  );

  static const TextStyle _subtitleStyle = TextStyle(fontSize: 12);

  // ── Sections ─────────────────────────────────────────────────────────────────

  Widget _appearanceSection() {
    return _sectionCard(
      title: 'APPEARANCE',
      children: [
        ListTile(
          leading: const Icon(JamIcons.wrench),
          title: Text('Themes', style: _titleStyle),
          subtitle: const Text('Accent colours, light & dark themes', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.push(const ThemeViewRoute()),
        ),
      ],
    );
  }

  Widget _downloadsSection() {
    return _sectionCard(
      title: 'DOWNLOADS',
      children: [
        ListTile(
          leading: const Icon(Icons.high_quality_outlined),
          title: Text('Download Quality', style: _titleStyle),
          subtitle: Text('Original resolution', style: _subtitleStyle),
        ),
      ],
    );
  }

  Widget _notificationsSection() {
    return _sectionCard(
      title: 'NOTIFICATIONS',
      children: [
        SwitchListTile(
          activeThumbColor: _accentColor,
          secondary: const Icon(Icons.wb_sunny_outlined),
          value: _notifWotd,
          title: Text('Wall of the Day', style: _titleStyle),
          subtitle: const Text('Daily wallpaper recommendation alert', style: TextStyle(fontSize: 12)),
          onChanged: (value) {
            setState(() => _notifWotd = value);
            _settingsLocal.set(PersistenceKeys.notifWotd, value);
          },
        ),
        SwitchListTile(
          activeThumbColor: _accentColor,
          secondary: const Icon(Icons.campaign_outlined),
          value: _notifPromo,
          title: Text('Promotional Alerts', style: _titleStyle),
          subtitle: const Text('New features, events & announcements', style: TextStyle(fontSize: 12)),
          onChanged: (value) {
            setState(() => _notifPromo = value);
            _settingsLocal.set(PersistenceKeys.notifPromo, value);
          },
        ),
      ],
    );
  }

  Widget _storageSection() {
    return _sectionCard(
      title: 'STORAGE',
      children: [
        ListTile(
          leading: const Icon(JamIcons.pie_chart_alt),
          title: Text('Clear Cache', style: _titleStyle),
          subtitle: const Text('Clear locally cached images', style: TextStyle(fontSize: 12)),
          onTap: () async {
            _trackSettingsAction(AnalyticsActionValue.clearCacheTapped);
            await _cacheMaintenance.clearTransientCache();
            toasts.codeSend('Cleared cache!');
          },
        ),
        ListTile(
          leading: const Icon(JamIcons.trash_alt),
          title: Text('Clear all Downloads', style: _titleStyle),
          subtitle: const Text('Remove all downloaded wallpapers', style: TextStyle(fontSize: 12)),
          onTap: () => _showClearDownloadsDialog(),
        ),
      ],
    );
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
        actions: [
          MaterialButton(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              bool deleted = false;
              try {
                final result = await PrismMediaHostApi().clearDownloads();
                deleted = result.success;
              } catch (e) {
                logger.d(e.toString());
              }
              Fluttertoast.showToast(
                msg: deleted ? 'Deleted all downloads!' : 'No downloads found.',
                toastLength: Toast.LENGTH_LONG,
                textColor: Colors.white,
                backgroundColor: deleted ? Colors.green[400] : Colors.red[400],
              );
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

  Widget _accountSection() {
    if (!app_state.prismUser.loggedIn) {
      return _sectionCard(
        title: 'ACCOUNT',
        children: [
          ListTile(
            leading: const Icon(JamIcons.log_in),
            title: Text('Sign in', style: _titleStyle),
            subtitle: const Text('Sign in to sync data across devices', style: TextStyle(fontSize: 12)),
            onTap: () async {
              _trackSettingsAction(AnalyticsActionValue.signInTapped);
              final loaderDialog = Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).primaryColor,
                  ),
                  width: MediaQuery.of(context).size.width * .7,
                  height: MediaQuery.of(context).size.height * .3,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              );
              showDialog(barrierDismissible: false, context: context, builder: (_) => loaderDialog);
              try {
                final String signInResult = await app_state.gAuth.signInWithGoogle();
                if (!mounted) return;
                if (signInResult == GoogleAuth.signInCancelledResult) {
                  Navigator.pop(context);
                  app_state.prismUser.loggedIn = false;
                  app_state.persistPrismUser();
                  _trackSettingsAuthResult(
                    action: AnalyticsActionValue.signInTapped,
                    result: EventResultValue.cancelled,
                    reason: AnalyticsReasonValue.userCancelled,
                  );
                  toasts.codeSend('Sign in cancelled.');
                  return;
                }
                toasts.codeSend('Login Successful!');
                _trackSettingsAuthResult(action: AnalyticsActionValue.signInTapped, result: EventResultValue.success);
                app_state.prismUser.loggedIn = true;
                app_state.persistPrismUser();
                Navigator.pop(context);
                main.RestartWidget.restartApp(context);
              } catch (e) {
                if (!mounted) return;
                logger.d(e);
                Navigator.pop(context);
                _trackSettingsAuthResult(
                  action: AnalyticsActionValue.signInTapped,
                  result: EventResultValue.failure,
                  reason: AnalyticsReasonValue.error,
                );
                app_state.prismUser.loggedIn = false;
                app_state.persistPrismUser();
                toasts.error('Something went wrong, please try again!');
              }
            },
          ),
        ],
      );
    }

    return _sectionCard(
      title: 'ACCOUNT',
      children: [
        ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundImage: app_state.prismUser.profilePhoto.isNotEmpty
                ? NetworkImage(app_state.prismUser.profilePhoto)
                : null,
            child: app_state.prismUser.profilePhoto.isEmpty ? const Icon(Icons.person, size: 16) : null,
          ),
          title: Text(app_state.prismUser.name, style: _titleStyle),
          subtitle: Text(app_state.prismUser.email, style: _subtitleStyle),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(JamIcons.heart),
          title: Text('Clear favourite walls', style: _titleStyle),
          subtitle: const Text('Remove all favourite wallpapers', style: TextStyle(fontSize: 12)),
          onTap: () {
            _trackSettingsAction(AnalyticsActionValue.clearFavouriteWallsTapped);
            _showClearFavWallsDialog();
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_rounded, color: Colors.red[400]),
          title: Text('Delete Account', style: _titleStyle.copyWith(color: Colors.red[400])),
          subtitle: const Text('Permanently delete your account and data', style: TextStyle(fontSize: 12)),
          onTap: () => _showDeleteAccountDialog(),
        ),
        ListTile(
          leading: Icon(JamIcons.log_out, color: _accentColor),
          title: Text('Logout', style: _titleStyle.copyWith(color: _accentColor)),
          subtitle: Text(app_state.prismUser.email, style: _subtitleStyle),
          onTap: () async {
            _trackSettingsAction(AnalyticsActionValue.logoutTapped);
            try {
              final bool signedOut = await app_state.gAuth.signOutGoogle();
              _trackSettingsAuthResult(
                action: AnalyticsActionValue.logoutTapped,
                result: signedOut ? EventResultValue.success : EventResultValue.failure,
                reason: signedOut ? null : AnalyticsReasonValue.error,
              );
              if (signedOut) {
                toasts.codeSend('Log out Successful!');
                final settingsLocal = getIt<SettingsLocalDataSource>();
                await settingsLocal.set('onboarded_v2_new', false);
                await settingsLocal.set('onboarding_v2_interests', '');
                if (context.mounted) {
                  // ignore: use_build_context_synchronously
                  main.RestartWidget.restartApp(context);
                }
              }
            } catch (error, stackTrace) {
              logger.e('Sign out failed from settings.', error: error, stackTrace: stackTrace);
              _trackSettingsAuthResult(
                action: AnalyticsActionValue.logoutTapped,
                result: EventResultValue.failure,
                reason: AnalyticsReasonValue.error,
              );
              toasts.error('Something went wrong, please try again!');
            }
          },
        ),
      ],
    );
  }

  void _showClearFavWallsDialog() {
    showModal(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        content: const SizedBox(
          height: 50,
          width: 250,
          child: Center(child: Text('Do you want to remove all your favourite wallpapers?')),
        ),
        actions: [
          MaterialButton(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            onPressed: () {
              _trackSettingsAction(AnalyticsActionValue.clearFavouriteWallsConfirmed);
              Navigator.of(ctx).pop();
              toasts.error('Cleared all favourite wallpapers!');
              context.favouriteWallsAdapter(listen: false).deleteData();
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
            'This will permanently delete your account data and sign you out.\n\nThis action cannot be undone.',
          ),
        ),
        actions: [
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
                      children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Deleting account...')],
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
              } catch (error) {
                if (!mounted) return;
                Navigator.pop(context);
                if (error is WrongAccountException) {
                  logger.w('Delete account cancelled: wrong account selected.', error: error);
                  toasts.error('Please select the account you are currently signed in with.');
                  return;
                }
                logger.e('Delete account failed.', error: error);
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

  Widget _adminSection() {
    if (!app_state.isAdminUser()) return const SizedBox.shrink();
    return _sectionCard(
      title: 'ADMIN',
      children: [
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text('Debug Panel', style: _titleStyle),
          subtitle: const Text('Logs, network, tools, storage inspector', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.pushPath('/debug-panel'),
        ),
        ListTile(
          leading: const Icon(JamIcons.file),
          title: Text('Remote Store Telemetry', style: _titleStyle),
          subtitle: const Text('Database usage and telemetry stats', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.push(const RemoteStoreTelemetryRoute()),
        ),
      ],
    );
  }

  Widget _aboutSection() {
    return _sectionCard(
      title: 'ABOUT',
      children: [
        ListTile(
          leading: const Icon(JamIcons.info),
          title: Text('About Prism', style: _titleStyle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.router.push(const AboutRoute()),
        ),
        ListTile(
          leading: const Icon(JamIcons.bug),
          title: Text('Report a Bug', style: _titleStyle),
          subtitle: const Text('Send a bug report via email', style: TextStyle(fontSize: 12)),
          onTap: () => _sendBugReport(),
        ),
        ListTile(
          leading: const Icon(JamIcons.refresh),
          title: Text('Restart App', style: _titleStyle),
          subtitle: const Text('Force the application to restart', style: TextStyle(fontSize: 12)),
          onTap: () {
            _trackSettingsAction(AnalyticsActionValue.restartAppTapped);
            main.RestartWidget.restartApp(context);
          },
        ),
      ],
    );
  }

  Future<void> _sendBugReport() async {
    if (!Platform.isAndroid) return;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final release = androidInfo.version.release;
    final sdkInt = androidInfo.version.sdkInt;
    final manufacturer = androidInfo.manufacturer;
    final model = androidInfo.model;
    final String zipPath = await zipLogs();
    if (zipPath.startsWith(logExportDisabledMarker)) {
      toasts.error('Log export is temporarily disabled.');
      return;
    }
    final String encryptedZipKey = zipPath.split('::::').first;
    final String encryptedZipPath = zipPath.split('::::').last;
    final deviceBody =
        '----x-x-x----<br>Device info -<br><br>Android version: Android $release<br>SDK Number: SDK $sdkInt<br>Device Manufacturer: $manufacturer<br>Device Model: $model<br>----x-x-x----<br><br>Enter the bug/issue below -<br><br>';
    final MailOptions mailOptions = MailOptions(
      body: deviceBody,
      subject: '[BUG REPORT::PRISM] - $encryptedZipKey',
      recipients: ['nightvibes33@users.noreply.github.com'],
      isHTML: true,
      attachments: [encryptedZipPath],
      appSchema: 'com.google.android.gm',
    );
    final MailerResponse response = await FlutterMailer.send(mailOptions);
    if (response != MailerResponse.android) {
      final MailOptions fallback = MailOptions(
        body: deviceBody,
        subject: '[BUG REPORT::PRISM]',
        recipients: ['nightvibes33@users.noreply.github.com'],
        isHTML: true,
        attachments: [zipPath],
      );
      await FlutterMailer.send(fallback);
    } else {
      toasts.codeSend('Bug report sent!');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
        children: [
          _appearanceSection(),
          _downloadsSection(),
          _notificationsSection(),
          _storageSection(),
          _accountSection(),
          _adminSection(),
          _aboutSection(),
        ],
      ),
    );
  }
}
