import 'package:Prism/auth/google_auth.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/remote_store/remote_store_runtime.dart';
import 'package:Prism/core/remote_store/remote_store_sentinels.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;

Stream<List<Map<String, dynamic>>> getUserProfile(String identifier) {
  final String value = identifier.trim();
  final bool isEmail = value.contains('@');
  final String v2Field = isEmail ? 'email' : 'username';

  return remoteStoreClient
      .watchQuery<Map<String, dynamic>>(
        RemoteStoreQuerySpec(
          collection: USER_NEW_COLLECTION,
          sourceTag: 'profile.stream.v2',
          filters: <RemoteStoreFilter>[RemoteStoreFilter(field: v2Field, op: RemoteStoreFilterOp.isEqualTo, value: value)],
          limit: 1,
          isStream: true,
        ),
        (data, docId) => <String, dynamic>{...data, '__docId': docId},
      )
      .asyncMap((event) async {
        if (event.isNotEmpty) {
          return event;
        }
        if (!isEmail) {
          final byEmailFallback = await remoteStoreClient.query<Map<String, dynamic>>(
            RemoteStoreQuerySpec(
              collection: USER_NEW_COLLECTION,
              sourceTag: 'profile.stream.v2_email_fallback',
              filters: <RemoteStoreFilter>[
                RemoteStoreFilter(field: 'email', op: RemoteStoreFilterOp.isEqualTo, value: value),
              ],
              limit: 1,
            ),
            (data, docId) => <String, dynamic>{...data, '__docId': docId},
          );
          if (byEmailFallback.isNotEmpty) {
            return byEmailFallback;
          }
        }
        return <Map<String, dynamic>>[];
      });
}

Future<void> follow(String email, String id) async {
  await remoteStoreClient.updateDoc(USER_NEW_COLLECTION, app_state.prismUser.id, {
    'following': RemoteStoreSentinels.arrayUnion(<Object?>[email]),
  }, sourceTag: 'profile.follow.current_user');
  await remoteStoreClient.updateDoc(USER_NEW_COLLECTION, id, {
    'followers': RemoteStoreSentinels.arrayUnion(<Object?>[app_state.prismUser.email]),
  }, sourceTag: 'profile.follow.target_user');
}

Future<void> unfollow(String email, String id) async {
  await remoteStoreClient.updateDoc(USER_NEW_COLLECTION, app_state.prismUser.id, {
    'following': RemoteStoreSentinels.arrayRemove(<Object?>[email]),
  }, sourceTag: 'profile.unfollow.current_user');
  await remoteStoreClient.updateDoc(USER_NEW_COLLECTION, id, {
    'followers': RemoteStoreSentinels.arrayRemove(<Object?>[app_state.prismUser.email]),
  }, sourceTag: 'profile.unfollow.target_user');
}
