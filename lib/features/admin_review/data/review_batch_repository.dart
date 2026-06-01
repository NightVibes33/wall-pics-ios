import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_document.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ReviewBatchRepository {
  static const int defaultBatchSize = 20;
  static const int maxUndoStack = 5;

  final RemoteStoreClient _remoteStoreClient;

  ReviewBatchRepository(this._remoteStoreClient);

  Future<List<RemoteStoreDocument>> fetchPendingWallsBatch({
    int limit = defaultBatchSize,
    String? startAfterDocId,
  }) async {
    final querySpec = RemoteStoreQuerySpec(
      collection: RemoteCollections.walls,
      sourceTag: 'review_batch.pending_walls',
      filters: <RemoteStoreFilter>[const RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: false)],
      orderBy: <RemoteStoreOrderBy>[const RemoteStoreOrderBy(field: 'createdAt', descending: true)],
      limit: limit,
      startAfterDocId: startAfterDocId,
    );

    final walls = await _remoteStoreClient.query(querySpec, (data, docId) => RemoteStoreDocument(docId, data));
    return walls;
  }

  Future<void> approveWall(RemoteStoreDocument wall, {List<String>? collections}) async {
    final payload = Map<String, dynamic>.from(wall.data());
    final wallCollections =
        collections ??
        (payload['collections'] as List?)
            ?.whereType<Object?>()
            .map((Object? item) => item?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        <String>[];

    await _remoteStoreClient.runBatch((RemoteStoreBatch batch) async {
      batch.updateDoc(RemoteCollections.walls, wall.id, <String, dynamic>{
        'review': true,
        'collections': wallCollections.isEmpty ? <String>['community'] : wallCollections,
        'reviewedAt': DateTime.now().toUtc(),
        'createdAt': DateTime.now().toUtc(),
      });
      _addNotificationToBatch(
        batch,
        modifier: _safeString(payload['email']),
        title: 'Wallpaper Approved',
        body: 'Your wallpaper "${_safeString(payload['title'])}" is now live!',
        imageUrl: _safeString(payload['wallpaper_thumb']),
        route: 'announcement',
      );
    }, sourceTag: 'review_batch.approve_wall');
  }

  Future<void> rejectWall(RemoteStoreDocument wall, {required String reason}) async {
    final payload = Map<String, dynamic>.from(wall.data());
    payload['rejectionReason'] = reason;
    payload['rejectedAt'] = DateTime.now().toUtc();

    await _remoteStoreClient.runBatch((RemoteStoreBatch batch) async {
      batch.addDoc(RemoteCollections.rejectedWalls, payload);
      batch.deleteDoc(RemoteCollections.walls, wall.id);
      _addNotificationToBatch(
        batch,
        modifier: _safeString(payload['email']),
        title: 'Wallpaper Rejected',
        body: reason,
        imageUrl: _safeString(payload['wallpaper_thumb']),
        route: 'announcement',
      );
    }, sourceTag: 'review_batch.reject_wall');
  }

  Future<void> updateWallCategory(String wallId, String category) async {
    await _remoteStoreClient.updateDoc(RemoteCollections.walls, wallId, <String, dynamic>{
      'category': category,
    }, sourceTag: 'review_batch.update_category');
  }

  Future<void> categorizeWalls(List<RemoteStoreDocument> walls) async {}

  Future<int> getPendingWallsCount() async {
    const querySpec = RemoteStoreQuerySpec(
      collection: RemoteCollections.walls,
      sourceTag: 'review_batch.pending_count',
      filters: <RemoteStoreFilter>[RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: false)],
    );
    final walls = await _remoteStoreClient.query(querySpec, (data, docId) => RemoteStoreDocument(docId, data));
    return walls.length;
  }

  void _addNotificationToBatch(
    RemoteStoreBatch batch, {
    required String modifier,
    required String title,
    required String body,
    required String imageUrl,
    String route = '',
  }) {
    if (modifier.isEmpty) return;
    batch.addDoc(RemoteCollections.notifications, <String, dynamic>{
      'modifier': modifier,
      'notification': <String, dynamic>{'title': title, 'body': body},
      'data': <String, dynamic>{
        'pageName': '',
        'arguments': const <Object?>[],
        'url': '',
        'imageUrl': imageUrl,
        'route': route,
      },
      'createdAt': DateTime.now().toUtc(),
    });
  }

  String _safeString(Object? value) => value?.toString() ?? '';
}
