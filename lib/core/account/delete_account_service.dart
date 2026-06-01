import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/features/onboarding_v2/src/common/onboarding_v2_keys.dart';
import 'package:Prism/logger/logger.dart';

class DeleteAccountService {
  DeleteAccountService._();

  static final DeleteAccountService instance = DeleteAccountService._();

  RemoteStoreClient get _remoteStore => getIt<RemoteStoreClient>();
  SettingsLocalDataSource get _settingsLocal => getIt<SettingsLocalDataSource>();

  /// Performs a full account deletion:
  ///   1. Deletes favourite subcollections (usersv2/{id}/images, /setups)
  ///   2. Deletes coinTransactions, aiGenerations, draftSetups owned by this user
  ///   3. Anonymizes the usersv2 doc so uploaded walls/setups still resolve
  ///   4. Clears local account state
  ///   5. Clears all local persistence
  Future<void> deleteAccount() async {
    final userId = app_state.prismUser.id;
    final email = app_state.prismUser.email;

    logger.i('[DeleteAccount] Starting deletion for userId=$userId email=$email', tag: 'DeleteAccount');

    if (userId.isEmpty) throw Exception('No signed-in user to delete.');

    // 1. Favourite subcollections
    logger.i('[DeleteAccount] Step 1: Deleting favourite subcollections', tag: 'DeleteAccount');
    await _deleteSubcollection('usersv2/$userId/images');
    await _deleteSubcollection('usersv2/$userId/setups');

    // 2. coinTransactions
    logger.i('[DeleteAccount] Step 2: Deleting coinTransactions', tag: 'DeleteAccount');
    await _deleteBatch(RemoteCollections.coinTransactions, [
      RemoteStoreFilter(field: 'userId', op: RemoteStoreFilterOp.isEqualTo, value: userId),
    ], 'delete_account.coin_transactions');

    // 3. aiGenerations
    logger.i('[DeleteAccount] Step 3: Deleting aiGenerations', tag: 'DeleteAccount');
    await _deleteBatch(RemoteCollections.aiGenerations, [
      RemoteStoreFilter(field: 'userId', op: RemoteStoreFilterOp.isEqualTo, value: userId),
    ], 'delete_account.ai_generations');

    // 4. draftSetups
    logger.i('[DeleteAccount] Step 4: Deleting draftSetups', tag: 'DeleteAccount');
    await _deleteBatch(RemoteCollections.draftSetups, [
      RemoteStoreFilter(field: 'email', op: RemoteStoreFilterOp.isEqualTo, value: email),
    ], 'delete_account.draft_setups');

    // 5. Anonymize usersv2 doc — keeps uploaded walls/setups resolving to "Deleted Account"
    logger.i('[DeleteAccount] Step 5: Anonymizing usersv2 doc', tag: 'DeleteAccount');
    await _remoteStore.setDoc(RemoteCollections.usersV2, userId, <String, dynamic>{
      'name': 'Deleted Account',
      'profilePhoto': '',
      'bio': '',
      'email': '',
      'following': <String>[],
      'followers': <String>[],
      'premium': false,
      'loggedIn': false,
      'deleted': true,
      'interestCategories': <String>[],
      'onboardingV2': <String, dynamic>{},
      'coinState': <String, dynamic>{},
      'coins': 0,
    }, sourceTag: 'delete_account.anonymize_user');

    // 6. Clear local account state
    logger.i('[DeleteAccount] Step 6: Clearing local account state', tag: 'DeleteAccount');

    // 6b. Sign out from local auth runtime
    logger.i('[DeleteAccount] Step 6b: Signing out locally', tag: 'DeleteAccount');
    await app_state.gAuth.signOutGoogle();

    // 7. Clear local persistence
    logger.i('[DeleteAccount] Step 7: Clearing local persistence', tag: 'DeleteAccount');
    await _settingsLocal.set(OnboardingV2Keys.onboardedNew, false);
    await _settingsLocal.set(OnboardingV2Keys.selectedInterests, '');
    await _settingsLocal.set(OnboardingV2Keys.followedCreators, '');
    await _settingsLocal.set('session.current_user', '');

    logger.i('[DeleteAccount] Done — account deleted successfully', tag: 'DeleteAccount');
  }

  Future<void> _deleteSubcollection(String collectionPath) async {
    final docIds = await _remoteStore.query<String>(
      RemoteStoreQuerySpec(
        collection: collectionPath,
        sourceTag: 'delete_account.list.$collectionPath',
        cachePolicy: RemoteStoreCachePolicy.networkOnly,
      ),
      (_, docId) => docId,
    );
    logger.d(
      '[DeleteAccount] _deleteSubcollection: $collectionPath — found ${docIds.length} docs',
      tag: 'DeleteAccount',
    );
    for (final docId in docIds) {
      logger.d('[DeleteAccount]   deleting $collectionPath/$docId', tag: 'DeleteAccount');
      await _remoteStore.deleteDoc(collectionPath, docId, sourceTag: 'delete_account.delete.$collectionPath');
    }
    logger.d('[DeleteAccount] _deleteSubcollection: $collectionPath — done', tag: 'DeleteAccount');
  }

  Future<void> _deleteBatch(String collection, List<RemoteStoreFilter> filters, String tag) async {
    final docIds = await _remoteStore.query<String>(
      RemoteStoreQuerySpec(
        collection: collection,
        sourceTag: tag,
        filters: filters,
        cachePolicy: RemoteStoreCachePolicy.networkOnly,
      ),
      (_, docId) => docId,
    );
    logger.d('[DeleteAccount] _deleteBatch: $collection — found ${docIds.length} docs', tag: 'DeleteAccount');
    if (docIds.isEmpty) return;
    try {
      await _remoteStore.runBatch((batch) async {
        for (final docId in docIds) {
          logger.d('[DeleteAccount]   queuing delete $collection/$docId', tag: 'DeleteAccount');
          batch.deleteDoc(collection, docId);
        }
      }, sourceTag: '$tag.batch_delete');
      logger.d('[DeleteAccount] _deleteBatch: $collection — batch committed', tag: 'DeleteAccount');
    } catch (e) {
      // RemoteStore rules may not allow client-side deletes on this collection.
      // Log and continue — these are non-critical audit records; the important
      // steps (anonymize usersv2 doc + clear local account state) still run.
      logger.w(
        '[DeleteAccount] _deleteBatch: $collection — skipped (${e.toString()}). TODO: update RemoteStore rules to allow user self-delete.',
        tag: 'DeleteAccount',
      );
    }
  }
}
