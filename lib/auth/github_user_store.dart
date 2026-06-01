import 'dart:convert';

import 'package:Prism/auth/userModel.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/env/env.dart';
import 'package:Prism/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class GitHubUserStore {
  const GitHubUserStore();

  static const Duration _timeout = Duration(seconds: 6);
  static const String _userAgent = 'WallPics-iOS';

  Future<PrismUsersV2> signInOrCreate({
    required String provider,
    required String providerUserId,
    required String email,
    required String displayName,
    String? photoUrl,
  }) async {
    final String userId = appUserIdFor(provider: provider, providerUserId: providerUserId);
    final String path = _pathForUserId(userId);
    final String now = DateTime.now().toUtc().toIso8601String();
    final String incomingEmail = email.trim();
    final String resolvedEmail = incomingEmail.isNotEmpty ? incomingEmail : _fallbackEmail(provider, providerUserId);
    final String resolvedName = _resolvedDisplayName(displayName, resolvedEmail, userId);
    final String resolvedPhoto = _resolvedPhotoUrl(photoUrl);

    final Map<String, dynamic> localData = _defaultUserData(
      userId: userId,
      email: resolvedEmail,
      displayName: resolvedName,
      photoUrl: resolvedPhoto,
      now: now,
    );

    if (!_isConfigured) {
      logger.w('GitHub user store is not configured; using local profile only.', tag: 'GitHubUserStore');
      return _userFromData(localData, userId: userId, email: resolvedEmail, displayName: resolvedName, photoUrl: resolvedPhoto);
    }

    try {
      final _GitHubJsonFile? existing = await _readJsonFile(path);
      final Map<String, dynamic> remoteData = <String, dynamic>{
        ...localData,
        if (existing != null) ...existing.data,
      };

      remoteData['id'] = _nonEmptyString(remoteData['id'], userId);
      remoteData['createdAt'] = _nonEmptyString(remoteData['createdAt'], now);
      remoteData['lastLoginAt'] = now;
      remoteData['loggedIn'] = true;
      remoteData['authProvider'] = provider;
      remoteData['providerUserId'] = providerUserId;
      remoteData['providerUserIdHash'] = _hash(providerUserId);
      remoteData['githubUserDocPath'] = path;
      remoteData['updatedAt'] = now;

      final String existingEmail = (remoteData['email'] ?? '').toString().trim();
      if (incomingEmail.isNotEmpty || existingEmail.isEmpty || _isSyntheticEmail(existingEmail)) {
        remoteData['email'] = resolvedEmail;
      }
      if (displayName.trim().isNotEmpty || (remoteData['name'] ?? '').toString().trim().isEmpty) {
        remoteData['name'] = resolvedName;
      }
      if ((photoUrl ?? '').trim().isNotEmpty || (remoteData['profilePhoto'] ?? '').toString().trim().isEmpty) {
        remoteData['profilePhoto'] = resolvedPhoto;
      }
      remoteData['username'] = _nonEmptyString(remoteData['username'], _usernameFrom(resolvedName, resolvedEmail, userId));
      remoteData['subscriptionTier'] = _nonEmptyString(remoteData['subscriptionTier'], 'free');

      await _writeJsonFile(path, remoteData, existing?.sha, message: 'Sync Wall Pics user $userId');
      return _userFromData(remoteData, userId: userId, email: resolvedEmail, displayName: resolvedName, photoUrl: resolvedPhoto);
    } catch (error, stackTrace) {
      logger.w(
        'GitHub user store sync failed; using local profile only.',
        tag: 'GitHubUserStore',
        error: error,
        stackTrace: stackTrace,
      );
      return _userFromData(localData, userId: userId, email: resolvedEmail, displayName: resolvedName, photoUrl: resolvedPhoto);
    }
  }

  Future<void> updateCurrentUserFields(Map<String, dynamic> data, {required String sourceTag}) async {
    final PrismUsersV2 user = app_state.prismUser;
    if (!_isConfigured || user.id.trim().isEmpty) {
      return;
    }

    final String path = _pathForUserId(user.id);
    final String now = DateTime.now().toUtc().toIso8601String();
    try {
      final _GitHubJsonFile? existing = await _readJsonFile(path);
      final Map<String, dynamic> merged = <String, dynamic>{
        if (existing != null) ...existing.data,
        ...user.toJson(),
        ...data,
        'id': user.id,
        'updatedAt': now,
        'lastSourceTag': sourceTag,
        'githubUserDocPath': path,
      };
      await _writeJsonFile(path, merged, existing?.sha, message: 'Update Wall Pics user ${user.id}');
    } catch (error, stackTrace) {
      logger.w(
        'GitHub user profile update failed.',
        tag: 'GitHubUserStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> markLoggedOut(String userId) async {
    final String trimmedUserId = userId.trim();
    if (!_isConfigured || trimmedUserId.isEmpty) {
      return;
    }

    final String path = _pathForUserId(trimmedUserId);
    final String now = DateTime.now().toUtc().toIso8601String();
    try {
      final _GitHubJsonFile? existing = await _readJsonFile(path);
      if (existing == null) {
        return;
      }
      final Map<String, dynamic> merged = <String, dynamic>{
        ...existing.data,
        'loggedIn': false,
        'lastLogoutAt': now,
        'updatedAt': now,
      };
      await _writeJsonFile(path, merged, existing.sha, message: 'Mark Wall Pics user logged out $trimmedUserId');
    } catch (error, stackTrace) {
      logger.w(
        'GitHub user logout update failed.',
        tag: 'GitHubUserStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, dynamic>?> getUserDataById(String userId) async {
    if (!_isConfigured || userId.trim().isEmpty) {
      return null;
    }
    final _GitHubJsonFile? file = await _readJsonFile(_pathForUserId(userId.trim()));
    return file?.data;
  }

  static String appUserIdFor({required String provider, required String providerUserId}) {
    final String normalizedProvider = _safeSegment(provider, fallback: 'auth');
    final String digest = _hash(providerUserId.trim().isEmpty ? provider : providerUserId);
    return '${normalizedProvider}_${digest.substring(0, 20)}';
  }

  Future<_GitHubJsonFile?> _readJsonFile(String path) async {
    final http.Response response = await http.get(_contentsUri(path), headers: _headers).timeout(_timeout);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw StateError('GitHub contents read failed with status ${response.statusCode}.');
    }

    final Map<String, dynamic> envelope = _asStringMap(jsonDecode(response.body));
    final String encoded = (envelope['content'] ?? '').toString().replaceAll('\n', '').trim();
    final String sha = (envelope['sha'] ?? '').toString();
    if (encoded.isEmpty || sha.isEmpty) {
      return null;
    }

    final String decoded = utf8.decode(base64Decode(encoded));
    return _GitHubJsonFile(data: _asStringMap(jsonDecode(decoded)), sha: sha);
  }

  Future<void> _writeJsonFile(String path, Map<String, dynamic> data, String? sha, {required String message}) async {
    final String prettyJson = const JsonEncoder.withIndent('  ').convert(data);
    final Map<String, dynamic> body = <String, dynamic>{
      'message': message,
      'content': base64Encode(utf8.encode(prettyJson)),
      if (sha != null && sha.isNotEmpty) 'sha': sha,
    };

    final http.Response response = await http
        .put(_contentsUri(path), headers: <String, String>{..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('GitHub contents write failed with status ${response.statusCode}.');
    }
  }

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
    };
  }

  static Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((Object? key, Object? mapValue) => MapEntry(key.toString(), mapValue));
    }
    return <String, dynamic>{};
  }

  static String _nonEmptyString(Object? value, String fallback) {
    final String candidate = (value ?? '').toString().trim();
    return candidate.isNotEmpty && candidate != 'null' ? candidate : fallback;
  }

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

  static String _pathForUserId(String userId) => 'users/${_safeSegment(userId, fallback: 'user')}.json';

  static String _safeSegment(String value, {required String fallback}) {
    final String safe = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return safe.isNotEmpty ? safe : fallback;
  }

  static String _hash(String value) => sha1.convert(utf8.encode(value)).toString();

  Uri _contentsUri(String path) => Uri.https('api.github.com', '/repos/$_owner/$_repo/contents/$path');

  Map<String, String> get _headers => <String, String>{
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer $_token',
    'User-Agent': _userAgent,
    'X-GitHub-Api-Version': '2022-11-28',
  };

  bool get _isConfigured => _token.isNotEmpty && _owner.isNotEmpty && _repo.isNotEmpty;

  String get _token => Env.normalize(Env.ghToken);

  String get _owner => Env.normalize(Env.ghUserName);

  String get _repo {
    final String usersRepo = Env.normalize(Env.ghRepoUsers);
    if (usersRepo.isNotEmpty) {
      return usersRepo;
    }
    return Env.normalize(Env.ghRepoWalls);
  }
}

class _GitHubJsonFile {
  const _GitHubJsonFile({required this.data, required this.sha});

  final Map<String, dynamic> data;
  final String sha;
}
