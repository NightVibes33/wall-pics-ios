import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/monitoring/sentry_user_scope.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/data/notifications/notifications.dart';
import 'package:Prism/logger/logger.dart';

class WrongAccountException implements Exception {
  final String selectedEmail;
  final String expectedEmail;
  const WrongAccountException({required this.selectedEmail, required this.expectedEmail});

  @override
  String toString() => 'WrongAccountException: selected $selectedEmail but expected $expectedEmail';
}

class GoogleAuth {
  static const String signInCancelledResult = 'signInWithGoogle canceled';

  String? name;
  String? email;
  String? imageUrl;
  String errorMsg = '';
  bool isLoggedIn = false;
  bool isLoading = false;

  Future<String> signInWithGoogle() async {
    isLoading = true;
    try {
      await analytics.track(
        const AuthLoginResultEvent(
          method: AuthMethodValue.google,
          result: EventResultValue.cancelled,
          reason: AnalyticsReasonValue.unknown,
          sourceContext: 'google_auth_removed',
        ),
      );
      logger.w('Google sign-in is disabled in this backend-free build.', tag: 'GoogleAuth');
      return signInCancelledResult;
    } finally {
      isLoading = false;
    }
  }

  Future<bool> signOutGoogle() async {
    clearInAppNotificationSyncGateAll();
    app_state.prismUser
      ..loggedIn = false
      ..premium = false
      ..subscriptionTier = 'free'
      ..id = ''
      ..email = ''
      ..username = ''
      ..name = ''
      ..bio = ''
      ..profilePhoto = app_state.defaultProfilePhotoUrl
      ..coverPhoto = ''
      ..followers = <String>[]
      ..following = <String>[]
      ..links = <String, String>{};
    await syncSentryUserScope(loggedIn: false, id: '', email: '');
    await app_state.persistPrismUser();
    await analytics.setUserId(null);
    await analytics.setUserProperty(name: AnalyticsUserProperty.subscriptionTier.wireName, value: 'free');
    await analytics.setUserProperty(name: AnalyticsUserProperty.isPremium.wireName, value: '0');
    return true;
  }

  Future<void> reauthenticateCurrentUser() async {}

  Future<bool> isSignedIn() async => false;

  Future<Map<String, dynamic>?> getUsersData(Object? user) async => null;
}
