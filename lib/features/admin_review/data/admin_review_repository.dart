import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_document.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/remote_store/remote_store_runtime.dart';

class AdminReviewRepository {
  const AdminReviewRepository();

  Stream<List<RemoteStoreDocument>> watchPendingWalls() {
    return remoteStoreClient.watchQuery<RemoteStoreDocument>(
      const RemoteStoreQuerySpec(
        collection: RemoteCollections.walls,
        sourceTag: 'admin_review.pending_walls',
        filters: <RemoteStoreFilter>[RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: false)],
        orderBy: <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'createdAt', descending: true)],
        isStream: true,
      ),
      (data, docId) => RemoteStoreDocument(docId, data),
    );
  }

  Stream<List<RemoteStoreDocument>> watchPendingSetups() {
    return remoteStoreClient.watchQuery<RemoteStoreDocument>(
      const RemoteStoreQuerySpec(
        collection: RemoteCollections.setups,
        sourceTag: 'admin_review.pending_setups',
        filters: <RemoteStoreFilter>[RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: false)],
        orderBy: <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'created_at', descending: true)],
        isStream: true,
      ),
      (data, docId) => RemoteStoreDocument(docId, data),
    );
  }

  Stream<List<RemoteStoreDocument>> watchOpenContentReports() {
    return remoteStoreClient.watchQuery<RemoteStoreDocument>(
      const RemoteStoreQuerySpec(
        collection: RemoteCollections.contentReports,
        sourceTag: 'admin_review.content_reports_open',
        filters: <RemoteStoreFilter>[RemoteStoreFilter(field: 'status', op: RemoteStoreFilterOp.isEqualTo, value: 'open')],
        orderBy: <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'createdAt', descending: true)],
        isStream: true,
      ),
      (data, docId) => RemoteStoreDocument(docId, data),
    );
  }

  Future<void> markContentReportReviewed(String reportDocId, {String? resolution}) async {
    await remoteStoreClient.updateDoc(RemoteCollections.contentReports, reportDocId, <String, dynamic>{
      'status': 'reviewed',
      'reviewedAt': DateTime.now().toUtc(),
      if (resolution != null && resolution.isNotEmpty) 'resolution': resolution,
    }, sourceTag: 'admin_review.mark_content_report_reviewed');
  }

  /// Returns true if the wall existed and was rejected; false if it was already missing.
  Future<bool> rejectWallByRemoteStoreDocumentId(String wallDocId, {required String reason}) async {
    final RemoteStoreDocument? wall = await remoteStoreClient.getById<RemoteStoreDocument>(
      RemoteCollections.walls,
      wallDocId,
      (Map<String, dynamic> data, String id) => RemoteStoreDocument(id, data),
      sourceTag: 'admin_review.reject_wall_by_doc_id',
    );
    if (wall == null) {
      return false;
    }
    await rejectWall(wall, reason: reason);
    return true;
  }

  Future<void> approveWall(RemoteStoreDocument wall) async {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(wall.data());
    final List<String> collections =
        (payload['collections'] as List?)
            ?.whereType<Object?>()
            .map((Object? item) => item?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    await remoteStoreClient.runBatch((RemoteStoreBatch batch) async {
      batch.updateDoc(RemoteCollections.walls, wall.id, <String, dynamic>{
        'review': true,
        'collections': collections.isEmpty ? <String>['community'] : collections,
        'reviewedAt': DateTime.now().toUtc(),
        'createdAt': DateTime.now().toUtc(),
      });
      _addUserNotificationToBatch(
        batch,
        modifier: _safeString(payload['email']),
        title: 'Wallpaper Approved',
        body: 'Your wallpaper has been approved and is now live.',
        imageUrl: _safeString(payload['wallpaper_thumb']),
        route: 'announcement',
      );
    }, sourceTag: 'admin_review.approve_wall');
  }

  Future<void> rejectWall(RemoteStoreDocument wall, {required String reason}) async {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(wall.data());
    payload['rejectionReason'] = reason;
    payload['rejectedAt'] = DateTime.now().toUtc();

    await remoteStoreClient.runBatch((RemoteStoreBatch batch) async {
      batch.addDoc(RemoteCollections.rejectedWalls, payload);
      batch.deleteDoc(RemoteCollections.walls, wall.id);
      _addUserNotificationToBatch(
        batch,
        modifier: _safeString(payload['email']),
        title: 'Wallpaper Rejected',
        body: reason,
        imageUrl: _safeString(payload['wallpaper_thumb']),
        route: 'announcement',
      );
    }, sourceTag: 'admin_review.reject_wall');
  }

  Future<void> approveSetup(RemoteStoreDocument setup) async {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(setup.data());
    await remoteStoreClient.runBatch((RemoteStoreBatch batch) async {
      batch.updateDoc(RemoteCollections.setups, setup.id, <String, dynamic>{
        'review': true,
        'reviewedAt': DateTime.now().toUtc(),
        'created_at': DateTime.now().toUtc(),
      });
      _addUserNotificationToBatch(
        batch,
        modifier: _safeString(payload['email']),
        title: 'Setup Approved',
        body: 'Your setup has been approved and is now live.',
        imageUrl: _safeString(payload['image']),
        route: 'announcement',
      );
    }, sourceTag: 'admin_review.approve_setup');
  }

  Future<void> rejectSetup(RemoteStoreDocument setup, {required String reason}) async {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(setup.data());
    payload['rejectionReason'] = reason;
    payload['rejectedAt'] = DateTime.now().toUtc();

    await remoteStoreClient.runBatch((RemoteStoreBatch batch) async {
      batch.addDoc(RemoteCollections.rejectedSetups, payload);
      batch.deleteDoc(RemoteCollections.setups, setup.id);
      _addUserNotificationToBatch(
        batch,
        modifier: _safeString(payload['email']),
        title: 'Setup Rejected',
        body: reason,
        imageUrl: _safeString(payload['image']),
        route: 'announcement',
      );
    }, sourceTag: 'admin_review.reject_setup');
  }

  void _addUserNotificationToBatch(
    RemoteStoreBatch batch, {
    required String modifier,
    required String title,
    required String body,
    required String imageUrl,
    String route = '',
    String wallId = '',
  }) {
    if (modifier.isEmpty) {
      return;
    }
    batch.addDoc(RemoteCollections.notifications, <String, dynamic>{
      'modifier': modifier,
      'notification': <String, dynamic>{'title': title, 'body': body},
      'data': <String, dynamic>{
        'pageName': '',
        'arguments': const <Object?>[],
        'url': '',
        'imageUrl': imageUrl,
        'route': route,
        if (wallId.isNotEmpty) 'wall_id': wallId,
      },
      'createdAt': DateTime.now().toUtc(),
    });
  }

  String _safeString(Object? value) => value?.toString() ?? '';
}
