import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/remote_store/remote_store_runtime.dart';
import 'package:Prism/logger/logger.dart';

List? collections;
List<Map<String, dynamic>>? anyCollectionWalls;
String? _lastCollectionCursorDocId;
String? currentCollectionName;
bool collectionHasMore = true;

Future<List?> getCollections() async {
  logger.d("Fetching collections!");
  collections = [];
  await remoteStoreClient
      .query<Map<String, dynamic>>(
        const RemoteStoreQuerySpec(
          collection: RemoteCollections.collections,
          sourceTag: 'collections.getCollections',
          orderBy: <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'lastEditTime', descending: true)],
          cachePolicy: RemoteStoreCachePolicy.memoryFirst,
          dedupeWindowMs: 30000,
        ),
        (data, _) => data,
      )
      .then((value) {
        for (final doc in value) {
          collections!.add(doc);
        }
      })
      .catchError((e) {
        logger.d(e.toString());
        logger.d("data done with error");
      });
  return collections;
}

Future<bool> getCollectionWithName(String name) async {
  logger.d("Fetching $name collection's first 24 walls");
  currentCollectionName = name;
  anyCollectionWalls = [];
  _lastCollectionCursorDocId = null;
  collectionHasMore = true;
  final List<Map<String, dynamic>> rows = await remoteStoreClient.query<Map<String, dynamic>>(
    RemoteStoreQuerySpec(
      collection: RemoteCollections.walls,
      sourceTag: 'collections.getCollectionWithName',
      filters: <RemoteStoreFilter>[
        const RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: true),
        RemoteStoreFilter(field: 'collections', op: RemoteStoreFilterOp.arrayContains, value: name),
      ],
      orderBy: const <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'createdAt', descending: true)],
      limit: 24,
      dedupeWindowMs: 1000,
    ),
    (data, docId) => <String, dynamic>{...data, '__docId': docId},
  );
  anyCollectionWalls = List<Map<String, dynamic>>.from(rows);
  collectionHasMore = rows.length == 24;
  if (rows.isNotEmpty) {
    _lastCollectionCursorDocId = rows.last['__docId']?.toString();
    for (final row in rows) {
      row.remove('__docId');
    }
  }
  return true;
}

Future<bool> seeMoreCollectionWithName() async {
  logger.d("Fetching $currentCollectionName collection's more walls");
  if (!collectionHasMore || _lastCollectionCursorDocId == null || _lastCollectionCursorDocId!.isEmpty) {
    collectionHasMore = false;
    return true;
  }
  final List<Map<String, dynamic>> rows = await remoteStoreClient.query<Map<String, dynamic>>(
    RemoteStoreQuerySpec(
      collection: RemoteCollections.walls,
      sourceTag: 'collections.seeMoreCollectionWithName',
      filters: <RemoteStoreFilter>[
        const RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: true),
        RemoteStoreFilter(field: 'collections', op: RemoteStoreFilterOp.arrayContains, value: currentCollectionName),
      ],
      orderBy: const <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'createdAt', descending: true)],
      startAfterDocId: _lastCollectionCursorDocId,
      limit: 24,
      dedupeWindowMs: 1000,
    ),
    (data, docId) => <String, dynamic>{...data, '__docId': docId},
  );
  collectionHasMore = rows.length == 24;
  if (rows.isNotEmpty) {
    _lastCollectionCursorDocId = rows.last['__docId']?.toString();
  }
  for (final row in rows) {
    row.remove('__docId');
    anyCollectionWalls!.add(row);
  }
  return true;
}
