import 'dart:convert';

import 'package:Prism/auth/userModel.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/env/env.dart';
import 'package:Prism/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class GitHubUserStore {
  const GitHubUserStore();

  static const Duration _timeout = Duration(seconds: 8);
  static const String _userAgent = 'WallPics-iOS';
  static String? _sessionToken;

  Future<PrismUsersV2> signInOrCreate({
    required String provider,
    required String providerUserId,
    required String email,
    required String displayName,
    required String identityToken,
    String? photoUrl,
  }) async {
    final String userId = appUserIdFor(provider: provider, providerUserId: providerUserId);
    final String now = DateTime.now().toUtc().toIso8601String();
    final String incomingEmail = email.trim();
    final String resolvedEmail = incomingEmail.isNotEmpty ? incomingEmail : _fallbackEmail(provider, providerUserId);
    final String resolvedName = _resolvedDisplayName(displayName, resolvedEmail, userId);
    final String resolvedPhoto = _resolvedPhotoUrl(photoUrl);

    final Map<String, dynamic> localData = _defaultUserData(
      userId: userId,
      provider: provider,
      providerUserId: providerUserId,
      email: resolvedEmail,
      displayName: resolvedName,
      photoUrl: resolvedPhoto,
      now: now,
    );

    if (!_isApiConfigured) {
      logger.w('User store API is not configured; using local profile only.', tag: 'GitHubUserStore');
      return _userFromData(localData, userId: userId, email: resolvedEmail, displayName: resolvedName, photoUrl: resolvedPhoto);
    }

    if (identityToken.trim().isEmpty) {
      throw StateError('User store API is configured, but $provider did not return an identity token.');
    }

    try {
      final Map<String, dynamic> response = await _postJson(
        '/v1/users/sign-in',
        <String, dynamic>{
          'provider': provider,
          'identityToken': identityToken,
          'providerUserIdHint': providerUserId,
          'emailHint': incomingEmail,
          'displayNameHint': displayName.trim(),
          'photoUrlHint': (photoUrl ?? '').trim(),
        },
      );
      _sessionToken = _stringValue(response['sessionToken']);
      final Map<String, dynamic> userData = _mapValue(response['user']);
      if (userData.isEmpty) {
        throw StateError('User store API returned no user document.');
      }
      return _userFromData(userData, userId: userId, email: resolvedEmail, displayName: resolvedName, photoUrl: resolvedPhoto);
    } catch (error, stackTrace) {
      logger.e(
        'User store API sign-in failed.',
        tag: 'GitHubUserStore',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> updateCurrentUserFields(Map<String, dynamic> data, {required String sourceTag}) async {
    final PrismUsersV2 user = app_state.prismUser;
    if (!_isApiConfigured || user.id.trim().isEmpty || (_sessionToken ?? '').isEmpty) {
      return;
    }

    try {
      final Map<String, dynamic> response = await _patchJson(
        '/v1/users/${Uri.encodeComponent(user.id)}',
        <String, dynamic>{'data': data, 'sourceTag': sourceTag},
      );
      final Map<String, dynamic> userData = _mapValue(response['user']);
      if (userData.isNotEmpty) {
        app_state.prismUser = PrismUsersV2.fromMapWithUser(
          userData,
          PrismAuthUser(uid: user.id, displayName: user.name, email: user.email, photoURL: user.profilePhoto),
        );
        await app_state.persistPrismUser();
      }
    } catch (error, stackTrace) {
      logger.w(
        'User store API profile update failed.',
        tag: 'GitHubUserStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> markLoggedOut(String userId) async {
    final String trimmedUserId = userId.trim();
    if (!_isApiConfigured || trimmedUserId.isEmpty || (_sessionToken ?? '').isEmpty) {
      _sessionToken = null;
      return;
    }

    try {
      await _postJson('/v1/users/${Uri.encodeComponent(trimmedUserId)}/logout', <String, dynamic>{});
    } catch (error, stackTrace) {
      logger.w(
        'User store API logout update failed.',
        tag: 'GitHubUserStore',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _sessionToken = null;
    }
  }

  Future<Map<String, dynamic>?> getUserDataById(String userId) async {
    if (!_isApiConfigured || userId.trim().isEmpty || (_sessionToken ?? '').isEmpty) {
      return null;
    }

    final http.Response response = await http.get(_apiUri('/v1/users/${Uri.encodeComponent(userId.trim())}'), headers: _headers).timeout(_timeout);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('User store API read failed with status ${response.statusCode}.');
    }
    final Map<String, dynamic> decoded = _mapValue(jsonDecode(response.body));
    return _mapValue(decoded['user']);
  }

  static String appUserIdFor({required String provider, required String providerUserId}) {
    final String normalizedProvider = _safeSegment(provider, fallback: 'auth');
    final String digest = _hash(providerUserId.trim().isEmpty ? provider : providerUserId);
    return '${normalizedProvider}_${digest.substring(0, 20)}';
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async {
    final http.Response response = await http
        .post(_apiUri(path), headers: <String, String>{..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(_timeout);
    return _decodeApiResponse(response);
  }

  Future<Map<String, dynamic>> _patchJson(String path, Map<String, dynamic> body) async {
    final http.Response response = await http
        .patch(_apiUri(path), headers: <String, String>{..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(_timeout);
    return _decodeApiResponse(response);
  }

  Map<String, dynamic> _decodeApiResponse(http.Response response) {
    final Map<String, dynamic> decoded = _mapValue(jsonDecode(response.body));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = _stringValue(decoded['error']);
      throw StateError(message.isNotEmpty ? message : 'User store API failed with status ${response.statusCode}.');
    }
    return decoded;
  }

  Uri _apiUri(String path) {
    final Uri base = Uri.parse(_apiBaseUrl);
    final String basePath = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    return base.replace(path: '$basePath$path');
  }

  Map<String, String> get _headers => <String, String>{
    'Accept': 'application/json',
    'User-Agent': _userAgent,
    if ((_sessionToken ?? '').isNotEmpty) 'Authorization': 'Bearer $_sessionToken',
  };

  bool get _isApiConfigured => _apiBaseUrl.isNotEmpty;

  String get _apiBaseUrl => Env.normalize(Env.userStoreApiBaseUrl);

  static PrismUsersV2 _userFromData(
    Map<String, dynamic> data, {
    required String userId,
    required String email,
    required String displayName,
    required String photoUrl,
  }) {
    final PrismAuthUser authUser = PrismAuthUser(uid: userId, displayName: displayName, email: email, photoURL: photoUrl);
    return PrismUsersV2.fromMapWithUser(data, authUser);
  }

  static Map<String, dynamic> _defaultUserData({
    required String userId,
    required String provider,
    required String providerUserId,
    required String email,
    required String displayName,
    required String photoUrl,
    required String now,
  }) {
    return <String, dynamic>{
      'name': displayName,
      'bio': '',
      'createdAt': now,
      'email': email,
      'username': _usernameFrom(displayName, email, userId),
      'followers': <String>[],
      'following': <String>[],
      'id': userId,
      'lastLoginAt': now,
      'links': <String, String>{},
      'premium': false,
      'loggedIn': true,
      'profilePhoto': photoUrl,
      'badges': <Map<String, dynamic>>[],
      'coins': 0,
      'subPrisms': <String>[],
      'transactions': <Map<String, dynamic>>[],
      'coverPhoto': '',
      'subscriptionTier': 'free',
      'uploadsWeekStart': '',
      'uploadsThisWeek': 0,
      'authProvider': provider,
      'providerUserIdHash': _hash(providerUserId),
      'githubUserDocPath': 'users/${_safeSegment(userId, fallback: 'user')}.json',
    };
  }

  static Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return <String, dynamic>{};
  }

  static String _stringValue(Object? value) => (value ?? '').toString().trim();

  static String _resolvedDisplayName(String displayName, String email, String userId) {
    final String candidate = displayName.trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
    final String emailName = email.contains('@') ? email.split('@').first : '';
    if (emailName.isNotEmpty && !_isSyntheticEmail(email)) {
      return emailName;
    }
    return 'Prism ${userId.substring(userId.length - 6)}';
  }

  static String _resolvedPhotoUrl(String? photoUrl) {
    final String candidate = (photoUrl ?? '').trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
    return app_state.defaultProfilePhotoUrl;
  }

  static String _usernameFrom(String displayName, String email, String userId) {
    final String source = displayName.trim().isNotEmpty
        ? displayName.trim()
        : email.contains('@') && !_isSyntheticEmail(email)
        ? email.split('@').first
        : userId;
    final String sanitized = source.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (sanitized.length >= 3) {
      return sanitized;
    }
    return 'user_${userId.substring(userId.length - 8)}';
  }

  static String _fallbackEmail(String provider, String providerUserId) {
    final String safeProvider = _safeSegment(provider, fallback: 'auth');
    return '$safeProvider-${_hash(providerUserId).substring(0, 12)}@users.prism.local';
  }

  static bool _isSyntheticEmail(String value) => value.trim().toLowerCase().endsWith('@users.prism.local');

  static String _safeSegment(String value, {required String fallback}) {
    final String safe = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return safe.isNotEmpty ? safe : fallback;
  }

  static String _hash(String value) => sha1.convert(utf8.encode(value)).toString();
}
