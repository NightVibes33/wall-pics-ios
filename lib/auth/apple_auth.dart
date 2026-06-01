import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/auth/github_user_store.dart';
import 'package:Prism/auth/userModel.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/monitoring/sentry_user_scope.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/env/env.dart';
import 'package:Prism/logger/logger.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppleAuth {
  static const String signInCancelledResult = 'signInWithApple canceled';

  final GitHubUserStore _userStore = const GitHubUserStore();

  Future<String> signInWithApple() async {
    logger.i('signInWithApple start', tag: 'AppleAuth');
    if (Env.sideloadBuild) {
      await analytics.track(
        const AuthLoginResultEvent(
          method: AuthMethodValue.apple,
          result: EventResultValue.cancelled,
          reason: AnalyticsReasonValue.unknown,
          sourceContext: 'apple_auth_sideload_disabled',
        ),
      );
      logger.w('Apple sign-in is disabled for unsigned sideload builds.', tag: 'AppleAuth');
      return signInCancelledResult;
    }
    try {
      final AuthorizationCredentialAppleID appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: <AppleIDAuthorizationScopes>[AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );

      final String providerUserId = (appleCredential.userIdentifier ?? '').trim();
      if (providerUserId.isEmpty) {
        throw StateError('Apple sign-in returned no stable user id.');
      }

      final String identityToken = (appleCredential.identityToken ?? '').trim();
      final String email = (appleCredential.email ?? '').trim();
      final String displayName = _resolvedDisplayName(
        givenName: appleCredential.givenName,
        familyName: appleCredential.familyName,
        email: email,
      );

      final PrismUsersV2 user = await _userStore.signInOrCreate(
        provider: 'apple',
        providerUserId: providerUserId,
        email: email,
        displayName: displayName,
        identityToken: identityToken,
        photoUrl: app_state.defaultProfilePhotoUrl,
      );
      app_state.prismUser = user;
      await app_state.persistPrismUser();
      await _finishSuccessfulSignIn();
      return 'signInWithApple succeeded: ${user.id}';
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        await analytics.track(
          const AuthLoginResultEvent(
            method: AuthMethodValue.apple,
            result: EventResultValue.cancelled,
            reason: AnalyticsReasonValue.userCancelled,
            sourceContext: 'apple_auth',
          ),
        );
        logger.i('signInWithApple canceled by user', tag: 'AppleAuth');
        return signInCancelledResult;
      }
      await analytics.track(
        const AuthLoginResultEvent(
          method: AuthMethodValue.apple,
          result: EventResultValue.failure,
          reason: AnalyticsReasonValue.error,
          sourceContext: 'apple_auth',
        ),
      );
      logger.e('signInWithApple authorization failed', tag: 'AppleAuth', error: e);
      rethrow;
    } catch (e, st) {
      await analytics.track(
        const AuthLoginResultEvent(
          method: AuthMethodValue.apple,
          result: EventResultValue.failure,
          reason: AnalyticsReasonValue.error,
          sourceContext: 'apple_auth',
        ),
      );
      logger.e('signInWithApple failed', tag: 'AppleAuth', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> _finishSuccessfulSignIn() async {
    await analytics.setUserId(app_state.prismUser.id);
    await analytics.setUserProperty(
      name: AnalyticsUserProperty.subscriptionTier.wireName,
      value: app_state.prismUser.subscriptionTier,
    );
    await analytics.setUserProperty(
      name: AnalyticsUserProperty.isPremium.wireName,
      value: app_state.prismUser.premium ? '1' : '0',
    );
    await analytics.track(
      const AuthLoginResultEvent(method: AuthMethodValue.apple, result: EventResultValue.success, sourceContext: 'apple_auth'),
    );
    await syncSentryUserScope(
      loggedIn: app_state.prismUser.loggedIn,
      id: app_state.prismUser.id,
      email: app_state.prismUser.email,
      username: app_state.prismUser.username,
    );
  }

  String _resolvedDisplayName({required String? givenName, required String? familyName, required String email}) {
    final String fullName = '${givenName ?? ''} ${familyName ?? ''}'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'Prism User';
  }
}
