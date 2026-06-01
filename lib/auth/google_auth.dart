import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/auth/github_user_store.dart';
import 'package:Prism/auth/userModel.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/coins/coins_service.dart';
import 'package:Prism/core/monitoring/sentry_user_scope.dart';
import 'package:Prism/core/purchases/purchases_service.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/data/notifications/notifications.dart';
import 'package:Prism/logger/logger.dart';
import 'package:google_sign_in/google_sign_in.dart';

class WrongAccountException implements Exception {
  final String selectedEmail;
  final String expectedEmail;
  const WrongAccountException({required this.selectedEmail, required this.expectedEmail});

  @override
  String toString() => 'WrongAccountException: selected $selectedEmail but expected $expectedEmail';
}

class GoogleAuth {
  static const String signInCancelledResult = 'signInWithGoogle canceled';

  final GoogleSignIn googleSignIn = GoogleSignIn.instance;
  final GitHubUserStore _userStore = const GitHubUserStore();
  bool _googleSignInInitialized = false;

  String? name;
  String? email;
  String? imageUrl;
  String errorMsg = '';
  bool isLoggedIn = false;
  bool isLoading = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) {
      return;
    }
    await googleSignIn.initialize();
    _googleSignInInitialized = true;
  }

  Future<String> signInWithGoogle() async {
    isLoading = true;
    logger.i('signInWithGoogle start', tag: 'GoogleAuth');
    try {
      await _ensureGoogleSignInInitialized();
      final GoogleSignInAccount googleAccount = await googleSignIn.authenticate();
      final GoogleSignInAuthentication googleAuthentication = googleAccount.authentication;
      final String identityToken = (googleAuthentication.idToken ?? '').trim();
      final String providerUserId = googleAccount.id.trim().isNotEmpty ? googleAccount.id : googleAccount.email;
      final String resolvedEmail = googleAccount.email.trim();
      final String resolvedDisplayName = _resolvedDisplayName(googleAccount.displayName, resolvedEmail);
      final String resolvedPhotoUrl = _resolvedPhotoUrl(googleAccount.photoUrl);

      if (providerUserId.trim().isEmpty) {
        throw StateError('Google sign-in returned no stable user id.');
      }
      if (resolvedEmail.isEmpty) {
        throw StateError('Google sign-in returned user without email.');
      }

      name = resolvedDisplayName;
      email = resolvedEmail;
      imageUrl = resolvedPhotoUrl;

      final PrismUsersV2 user = await _userStore.signInOrCreate(
        provider: 'google',
        providerUserId: providerUserId,
        email: resolvedEmail,
        displayName: resolvedDisplayName,
        identityToken: identityToken,
        photoUrl: resolvedPhotoUrl,
      );
      app_state.prismUser = user;
      await app_state.persistPrismUser();
      await _finishSuccessfulSignIn(AuthMethodValue.google, 'google_auth');
      return 'signInWithGoogle succeeded: ${user.id}';
    } catch (e, st) {
      if (_isSignInCancelled(e)) {
        await analytics.track(
          const AuthLoginResultEvent(
            method: AuthMethodValue.google,
            result: EventResultValue.cancelled,
            reason: AnalyticsReasonValue.userCancelled,
            sourceContext: 'google_auth',
          ),
        );
        logger.i('signInWithGoogle canceled by user', tag: 'GoogleAuth');
        return signInCancelledResult;
      }
      await analytics.track(
        const AuthLoginResultEvent(
          method: AuthMethodValue.google,
          result: EventResultValue.failure,
          reason: AnalyticsReasonValue.error,
          sourceContext: 'google_auth',
        ),
      );
      logger.e('signInWithGoogle failed', tag: 'GoogleAuth', error: e, stackTrace: st);
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  bool _isSignInCancelled(Object error) {
    if (error is GoogleSignInException) {
      return error.code == GoogleSignInExceptionCode.canceled || error.code == GoogleSignInExceptionCode.unknownError;
    }
    final String message = error.toString().toLowerCase();
    return message.contains('user canceled') ||
        message.contains('cancelled') ||
        message.contains('canceled') ||
        message.contains('no credential') ||
        message.contains('no credentials available');
  }

  Future<bool> signOutGoogle() async {
    clearInAppNotificationSyncGateAll();
    final String existingUserId = app_state.prismUser.id;
    try {
      await _ensureGoogleSignInInitialized();
      await googleSignIn.signOut();
    } catch (e, st) {
      logger.w(
        'Google signOut failed; continuing local sign-out cleanup.',
        tag: 'GoogleAuth',
        error: e,
        stackTrace: st,
      );
    }

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
    try {
      await PurchasesService.instance.logOut();
    } catch (e, st) {
      logger.w(
        'RevenueCat signOut failed; continuing local sign-out cleanup.',
        tag: 'GoogleAuth',
        error: e,
        stackTrace: st,
      );
    }
    await _userStore.markLoggedOut(existingUserId);
    await analytics.setUserId(null);
    await analytics.setUserProperty(name: AnalyticsUserProperty.subscriptionTier.wireName, value: 'free');
    await analytics.setUserProperty(name: AnalyticsUserProperty.isPremium.wireName, value: '0');
    logger.d('User Sign Out');
    return true;
  }

  Future<void> reauthenticateCurrentUser() async {
    await _ensureGoogleSignInInitialized();
    final GoogleSignInAccount googleAccount = await googleSignIn.authenticate();
    final String currentEmail = app_state.prismUser.email.trim();
    if (currentEmail.isNotEmpty && googleAccount.email.trim() != currentEmail) {
      throw WrongAccountException(selectedEmail: googleAccount.email, expectedEmail: currentEmail);
    }
  }

  Future<bool> isSignedIn() async => app_state.prismUser.loggedIn && app_state.prismUser.id.trim().isNotEmpty;

  Future<Map<String, dynamic>?> getUsersData(Object? user) async {
    if (user is PrismAuthUser) {
      return _userStore.getUserDataById(user.uid);
    }
    if (user is String) {
      return _userStore.getUserDataById(user);
    }
    return null;
  }

  Future<void> _finishSuccessfulSignIn(AuthMethodValue method, String sourceContext) async {
    await analytics.setUserId(app_state.prismUser.id);
    await analytics.setUserProperty(
      name: AnalyticsUserProperty.subscriptionTier.wireName,
      value: app_state.prismUser.subscriptionTier,
    );
    await analytics.setUserProperty(
      name: AnalyticsUserProperty.isPremium.wireName,
      value: app_state.prismUser.premium ? '1' : '0',
    );
    await analytics.track(AuthLoginResultEvent(method: method, result: EventResultValue.success, sourceContext: sourceContext));
    unawaited(() async {
      await PurchasesService.instance.checkAndPersistPremium();
      await CoinsService.instance.bootstrapForCurrentUser();
      await CoinsService.instance.refreshBalance();
      await CoinsService.instance.claimDailyLoginAndStreakIfEligible();
      await CoinsService.instance.maybeAwardProDailyBonus();
      await CoinsService.instance.processPendingReferralIfEligible();
    }());
    await syncSentryUserScope(
      loggedIn: app_state.prismUser.loggedIn,
      id: app_state.prismUser.id,
      email: app_state.prismUser.email,
      username: app_state.prismUser.username,
    );
  }

  String _resolvedDisplayName(String? displayName, String email) {
    final String candidate = (displayName ?? '').trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'Prism User';
  }

  String _resolvedPhotoUrl(String? photoUrl) {
    final String candidate = (photoUrl ?? '').trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
    return app_state.defaultProfilePhotoUrl;
  }
}
