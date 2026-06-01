import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/features/user_search/domain/entities/user_search_user.dart';
import 'package:Prism/features/user_search/domain/repositories/user_search_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: UserSearchRepository)
class UserSearchRepositoryImpl implements UserSearchRepository {
  UserSearchRepositoryImpl(this._remoteStoreClient);

  final RemoteStoreClient _remoteStoreClient;

  @override
  Future<Result<List<UserSearchUser>>> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Result.success(const <UserSearchUser>[]);
    }

    try {
      final rangeEnd = '$trimmed\uf8ff';

      final results = await Future.wait([
        _remoteStoreClient.query<Map<String, dynamic>>(
          RemoteStoreQuerySpec(
            collection: RemoteCollections.usersV2,
            sourceTag: 'user_search.search_users_by_name',
            filters: <RemoteStoreFilter>[
              RemoteStoreFilter(field: 'name', op: RemoteStoreFilterOp.isGreaterThanOrEqualTo, value: trimmed),
              RemoteStoreFilter(field: 'name', op: RemoteStoreFilterOp.isLessThanOrEqualTo, value: rangeEnd),
            ],
            limit: 20,
          ),
          (data, docId) => <String, dynamic>{...data, '__docId': docId},
        ),
        _remoteStoreClient.query<Map<String, dynamic>>(
          RemoteStoreQuerySpec(
            collection: RemoteCollections.usersV2,
            sourceTag: 'user_search.search_users_by_username',
            filters: <RemoteStoreFilter>[
              RemoteStoreFilter(field: 'username', op: RemoteStoreFilterOp.isGreaterThanOrEqualTo, value: trimmed),
              RemoteStoreFilter(field: 'username', op: RemoteStoreFilterOp.isLessThanOrEqualTo, value: rangeEnd),
            ],
            limit: 20,
          ),
          (data, docId) => <String, dynamic>{...data, '__docId': docId},
        ),
      ]);

      // Merge and deduplicate by doc ID
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final row in [...results[0], ...results[1]]) {
        final id = (row['__docId'] ?? '').toString();
        if (seen.add(id)) merged.add(row);
      }

      final users = merged
          .map((data) {
            return UserSearchUser(
              id: (data['id'] ?? data['__docId'] ?? '').toString(),
              name: (data['name'] ?? '').toString(),
              username: (data['username'] ?? '').toString(),
              email: (data['email'] ?? '').toString(),
              profilePhoto: (data['profilePhoto'] ?? '').toString(),
              coverPhoto: data['coverPhoto']?.toString(),
              bio: (data['bio'] ?? '').toString(),
              links:
                  (data['links'] as Map?)?.map((key, value) => MapEntry(key.toString(), value?.toString() ?? '')) ??
                  const <String, String>{},
              followers:
                  (data['followers'] as List?)
                      ?.whereType<Object?>()
                      .map((Object? value) => value?.toString() ?? '')
                      .where((value) => value.isNotEmpty)
                      .toList(growable: false) ??
                  const <String>[],
              following:
                  (data['following'] as List?)
                      ?.whereType<Object?>()
                      .map((Object? value) => value?.toString() ?? '')
                      .where((value) => value.isNotEmpty)
                      .toList(growable: false) ??
                  const <String>[],
              premium: (data['premium'] ?? false) as bool,
            );
          })
          .toList(growable: false);

      return Result.success(users);
    } catch (error) {
      return Result.error(ServerFailure('Unable to search users: $error'));
    }
  }
}
