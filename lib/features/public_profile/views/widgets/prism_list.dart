import 'dart:async';
import 'dart:io' show Platform;

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/platform/share_service.dart';
import 'package:Prism/core/utils/url_launcher_compat.dart';
import 'package:Prism/core/widgets/popup/changelogPopUp.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:animations/animations.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mailer/flutter_mailer.dart';

class PrismList extends StatelessWidget {
  void _trackAction(AnalyticsActionValue action, {required String sourceContext}) {
    unawaited(
      analytics.track(
        SurfaceActionTappedEvent(
          surface: AnalyticsSurfaceValue.profilePrismList,
          action: action,
          sourceContext: sourceContext,
        ),
      ),
    );
  }

  void _trackExternalLink(LinkDestinationValue destination, {required bool launched, required String sourceContext}) {
    unawaited(
      analytics.track(
        ExternalLinkOpenResultEvent(
          surface: AnalyticsSurfaceValue.profilePrismList,
          destination: destination,
          result: launched ? EventResultValue.success : EventResultValue.failure,
          reason: launched ? null : AnalyticsReasonValue.error,
          sourceContext: sourceContext,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(JamIcons.info),
          title: Text(
            "What's new?",
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w500,
              fontFamily: "Proxima Nova",
            ),
          ),
          subtitle: const Text("Check out the changelog", style: TextStyle(fontSize: 12)),
          onTap: () {
            _trackAction(AnalyticsActionValue.actionChipTapped, sourceContext: 'profile_prism_list_whats_new');
            showChangelog(context, () {});
          },
        ),
        ListTile(
          leading: const Icon(JamIcons.share_alt),
          title: Text(
            "Share Prism!",
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w500,
              fontFamily: "Proxima Nova",
            ),
          ),
          subtitle: const Text("Quick link to pass on to your friends and enemies", style: TextStyle(fontSize: 12)),
          onTap: () async {
            _trackAction(AnalyticsActionValue.drawerSharePrismTapped, sourceContext: 'profile_prism_list_share');
            await ShareService.shareText(
              text:
                  "Fall in love with Android customisation again! Check out Prism -\nhttps://play.google.com/store/apps/details?id=com.hash.prism",
              context: context,
            );
          },
        ),
        ListTile(
          leading: const Icon(JamIcons.users),
          title: Text(
            "Privacy Policy",
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w500,
              fontFamily: "Proxima Nova",
            ),
          ),
          subtitle: const Text("Read Prism' Privacy Policy.", style: TextStyle(fontSize: 12)),
          onTap: () async {
            _trackAction(AnalyticsActionValue.actionChipTapped, sourceContext: 'profile_prism_list_privacy');
            final bool launched = await launchUrl(
              Uri.parse("https://github.com/NightVibes33/prism-ios/blob/main/PRIVACY.md"),
            );
            _trackExternalLink(
              LinkDestinationValue.github,
              launched: launched,
              sourceContext: 'profile_prism_list_privacy',
            );
          },
        ),
        ListTile(
          leading: const Icon(JamIcons.database),
          title: Text(
            "Catalog",
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w500,
              fontFamily: "Proxima Nova",
            ),
          ),
          subtitle: const Text("Prism uses the Prism catalog API for wallpapers.", style: TextStyle(fontSize: 12)),
          onTap: () {
            _trackAction(AnalyticsActionValue.actionChipTapped, sourceContext: 'profile_prism_list_catalog');
            showModal(
              context: context,
              builder: (context) => AlertDialog(
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                content: const SizedBox(
                  height: 110,
                  width: 250,
                  child: Center(
                    child: Text(
                      'Prism catalog content is delivered through the Prism API.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(JamIcons.bug),
          title: Text(
            "Report a bug",
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w500,
              fontFamily: "Proxima Nova",
            ),
          ),
          subtitle: const Text("Tell us if you found out a bug", style: TextStyle(fontSize: 12)),
          onTap: () async {
            _trackAction(
              AnalyticsActionValue.drawerContactSupportTapped,
              sourceContext: 'profile_prism_list_report_bug',
            );
            if (Platform.isAndroid) {
              final androidInfo = await DeviceInfoPlugin().androidInfo;
              final release = androidInfo.version.release;
              final sdkInt = androidInfo.version.sdkInt;
              final manufacturer = androidInfo.manufacturer;
              final model = androidInfo.model;
              logger.d('Android $release (SDK $sdkInt), $manufacturer $model');
              final String zipPath = await zipLogs();
              if (zipPath.startsWith(logExportDisabledMarker)) {
                toasts.error('Log export is temporarily disabled.');
                return;
              }
              final String encryptedZipPath = zipPath.split("::::").last;
              final String encryptedZipKey = zipPath.split("::::").first;
              final MailOptions mailOptions = MailOptions(
                body:
                    '----x-x-x----<br>Device info -<br><br>Android version: Android $release<br>SDK Number: SDK $sdkInt<br>Device Manufacturer: $manufacturer<br>Device Model: $model<br>----x-x-x----<br><br>Enter the bug/issue below -<br><br>',
                subject: '[BUG REPORT::PRISM] - $encryptedZipKey',
                recipients: ['nightvibes33@users.noreply.github.com'],
                isHTML: true,
                attachments: [encryptedZipPath],
                appSchema: 'com.google.android.gm',
              );
              final MailerResponse response = await FlutterMailer.send(mailOptions);
              if (response != MailerResponse.android) {
                final MailOptions mailOptions = MailOptions(
                  body:
                      '----x-x-x----<br>Device info -<br><br>Android version: Android $release<br>SDK Number: SDK $sdkInt<br>Device Manufacturer: $manufacturer<br>Device Model: $model<br>----x-x-x----<br><br>Enter the bug/issue below -<br><br>',
                  subject: '[BUG REPORT::PRISM]',
                  recipients: ['nightvibes33@users.noreply.github.com'],
                  isHTML: true,
                  attachments: [zipPath],
                );
                await FlutterMailer.send(mailOptions);
              } else {
                toasts.codeSend("Bug report sent!");
              }
            }
          },
        ),
      ],
    );
  }
}
