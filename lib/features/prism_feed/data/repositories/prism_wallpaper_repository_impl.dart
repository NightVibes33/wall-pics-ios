import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/persistence/data_sources/feed_cache_local_data_source.dart';
import 'package:Prism/core/user_blocks/blocked_creators_filter.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/features/prism_feed/data/dtos/prism_wall_doc_dto.dart';
import 'package:Prism/features/prism_feed/data/mappers/prism_wall_doc_mapper.dart';
import 'package:Prism/features/prism_feed/domain/repositories/prism_wallpaper_repository.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/user_blocks/domain/repositories/user_block_repository.dart';
import 'package:Prism/features/wallpics_catalog/data/wallpics_catalog_data_source.dart';
import 'package:Prism/logger/logger.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: PrismWallpaperRepository)
class PrismWallpaperRepositoryImpl implements PrismWallpaperRepository {
  PrismWallpaperRepositoryImpl(this._remoteStoreClient, this._feedCacheLocal, this._userBlockRepository);

  final RemoteStoreClient _remoteStoreClient;
  final FeedCacheLocalDataSource _feedCacheLocal;
  final UserBlockRepository _userBlockRepository;

  String? _lastDocId;
  bool _hasMore = true;
  static const int _pageSize = 24;
  static const int _feedTtlHours = 6;

  @override
  bool get hasMore => _hasMore;

  @override
  Future<Result<List<PrismWallpaper>>> fetchFeed({required bool refresh}) async {
    if (refresh) {
      _lastDocId = null;
      _hasMore = true;
    }

    logger.d('[PrismWallpaperRepository] fetchFeed', fields: <String, Object?>{'refresh': refresh});

    try {
      final wallpicsPage = await WallpicsCatalogDataSource.instance.fetchHomePage(refresh: refresh);
      final localWalls = wallpicsPage.items
          .whereType<PrismFeedItem>()
          .map((item) => item.wallpaper)
          .toList(growable: false);
      if (localWalls.isNotEmpty) {
        _hasMore = wallpicsPage.hasMore;
        logger.i('[PrismWallpaperRepository] fetchFeed wallpics catalog success', fields: <String, Object?>{'count': localWalls.length});
        return Result.success(localWalls);
      }
    } catch (error, stackTrace) {
      logger.w('[PrismWallpaperRepository] Wallpics catalog unavailable; falling back to RemoteStore', error: error, stackTrace: stackTrace);
    }

    try {
      final Set<String> blocked = await _blockedCreatorEmails(waitForInitialLoad: true);
      final List<_PrismRow> traversedRows = <_PrismRow>[];
      final List<PrismWallpaper> visibleWalls = <PrismWallpaper>[];
      String? nextCursor = refresh ? null : _lastDocId;
      bool hasMoreSourceRows = false;

      while (visibleWalls.length < _pageSize) {
        final List<_PrismRow> batch = await _remoteStoreClient.query<_PrismRow>(
          RemoteStoreQuerySpec(
            collection: RemoteCollections.walls,
            sourceTag: 'PrismWallpaperRepository.fetchFeed',
            filters: const <RemoteStoreFilter>[
              RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: true),
            ],
            orderBy: const <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'createdAt', descending: true)],
            startAfterDocId: nextCursor,
            limit: _pageSize,
            dedupeWindowMs: 1000,
            cachePolicy: refresh ? RemoteStoreCachePolicy.networkOnly : RemoteStoreCachePolicy.memoryFirst,
          ),
          (data, docId) => _PrismRow(docId: docId, doc: PrismWallDocDto.fromJson(data)),
        );
        if (batch.isEmpty) {
          hasMoreSourceRows = false;
          break;
        }

        for (int i = 0; i < batch.length; i += 1) {
          final _PrismRow row = batch[i];
          traversedRows.add(row);
          nextCursor = row.docId;

          final PrismWallpaper wallpaper = row.doc.toDomain(docId: row.docId);
          if (!BlockedCreatorsFilter.hidesCreatorEmail(wallpaper.core.authorEmail, blocked)) {
            visibleWalls.add(wallpaper);
          }

          if (visibleWalls.length == _pageSize) {
            hasMoreSourceRows = i < batch.length - 1 || batch.length == _pageSize;
            break;
          }
        }

        if (visibleWalls.length == _pageSize) {
          break;
        }
        if (batch.length < _pageSize) {
          hasMoreSourceRows = false;
          break;
        }
        hasMoreSourceRows = true;
      }

      _lastDocId = traversedRows.isEmpty ? null : traversedRows.last.docId;
      _hasMore = hasMoreSourceRows;
      await _writeCache(rows: traversedRows, hasMore: _hasMore, lastDocId: _lastDocId);
      logger.i('[PrismWallpaperRepository] fetchFeed success', fields: <String, Object?>{'count': visibleWalls.length});
      return Result.success(visibleWalls);
    } catch (error, stackTrace) {
      final cached = await _readCached();
      if (cached != null) {
        logger.w(
          '[PrismWallpaperRepository] remote fetch failed; returning cached snapshot',
          error: error,
          stackTrace: stackTrace,
        );
        return Result.success(cached);
      }
      logger.e('[PrismWallpaperRepository] fetchFeed failed', error: error, stackTrace: stackTrace);
      return Result.error(ServerFailure('Failed to fetch Prism feed: $error'));
    }
  }

  @override
  Future<Result<List<PrismWallpaper>>> fetchStreakShopWallpapers() async {
    try {
      final List<_PrismRow> rows = await _remoteStoreClient.query<_PrismRow>(
        const RemoteStoreQuerySpec(
          collection: RemoteCollections.walls,
          sourceTag: 'PrismWallpaperRepository.fetchStreakShop',
          filters: <RemoteStoreFilter>[
            RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: true),
            RemoteStoreFilter(field: 'isStreakExclusive', op: RemoteStoreFilterOp.isEqualTo, value: true),
          ],
          limit: 50,
          dedupeWindowMs: 1000,
        ),
        (data, docId) => _PrismRow(docId: docId, doc: PrismWallDocDto.fromJson(data)),
      );
      final Set<String> blocked = await _blockedCreatorEmails(waitForInitialLoad: true);
      final List<PrismWallpaper> walls = rows
          .map((row) => row.doc.toDomain(docId: row.docId))
          .where((w) => !BlockedCreatorsFilter.hidesCreatorEmail(w.core.authorEmail, blocked))
          .toList(growable: false);
      walls.sort((a, b) {
        final aDays = a.requiredStreakDays ?? 999;
        final bDays = b.requiredStreakDays ?? 999;
        return aDays.compareTo(bDays);
      });
      logger.d(
        '[PrismWallpaperRepository] fetchStreakShopWallpapers',
        fields: <String, Object?>{'count': walls.length},
      );
      return Result.success(walls);
    } catch (error, stackTrace) {
      logger.e('[PrismWallpaperRepository] fetchStreakShopWallpapers failed', error: error, stackTrace: stackTrace);
      return Result.error(ServerFailure('Failed to fetch streak shop: $error'));
    }
  }

  @override
  Future<Result<PrismWallpaper?>> fetchById(String id) async {
    try {
      final local = await WallpicsCatalogDataSource.instance.fetchById(id);
      if (local != null) {
        return Result.success(local);
      }
    } catch (error, stackTrace) {
      logger.w('[PrismWallpaperRepository] Wallpics fetchById fallback to RemoteStore', error: error, stackTrace: stackTrace);
    }

    try {
      final List<_PrismRow> results = await _remoteStoreClient.query<_PrismRow>(
        RemoteStoreQuerySpec(
          collection: RemoteCollections.walls,
          sourceTag: 'PrismWallpaperRepository.fetchById',
          filters: <RemoteStoreFilter>[
            RemoteStoreFilter(field: 'id', op: RemoteStoreFilterOp.isEqualTo, value: id),
            const RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: true),
          ],
          limit: 1,
        ),
        (data, docId) => _PrismRow(docId: docId, doc: PrismWallDocDto.fromJson(data)),
      );
      if (results.isEmpty) {
        return Result.success(null);
      }
      final PrismWallpaper wall = results.first.doc.toDomain(docId: results.first.docId);
      final Set<String> blocked = await _blockedCreatorEmails(waitForInitialLoad: true);
      if (BlockedCreatorsFilter.hidesCreatorEmail(wall.core.authorEmail, blocked)) {
        return Result.success(null);
      }
      return Result.success(wall);
    } catch (error, stackTrace) {
      logger.e('[PrismWallpaperRepository] fetchById failed', error: error, stackTrace: stackTrace);
      return Result.error(ServerFailure('Failed to fetch Prism wallpaper by id: $error'));
    }
  }

  @override
  Future<Result<PrismWallpaper?>> fetchByDocumentId(String documentId) async {
    if (documentId.isEmpty) {
      return Result.success(null);
    }
    try {
      final Map<String, dynamic>? data = await _remoteStoreClient.getById<Map<String, dynamic>>(
        RemoteCollections.walls,
        documentId,
        (d, _) => d,
        sourceTag: 'PrismWallpaperRepository.fetchByDocumentId',
      );
      if (data == null) {
        return Result.success(null);
      }
      final PrismWallpaper wallpaper = PrismWallDocDto.fromJson(data).toDomain(docId: documentId);
      final Set<String> blocked = await _blockedCreatorEmails(waitForInitialLoad: true);
      if (BlockedCreatorsFilter.hidesCreatorEmail(wallpaper.core.authorEmail, blocked)) {
        return Result.success(null);
      }
      return Result.success(wallpaper);
    } catch (error, stackTrace) {
      logger.e('[PrismWallpaperRepository] fetchByDocumentId failed', error: error, stackTrace: stackTrace);
      return Result.error(ServerFailure('Failed to fetch Prism wallpaper by document id: $error'));
    }
  }

  Future<void> _writeCache({required List<_PrismRow> rows, required bool hasMore, required String? lastDocId}) {
    return _feedCacheLocal.write(
      source: 'prism',
      scope: 'main',
      ttlHours: _feedTtlHours,
      payload: <String, Object?>{
        'rows': rows
            .map((row) => <String, Object?>{'docId': row.docId, 'doc': row.doc.toJson()})
            .toList(growable: false),
        'hasMore': hasMore,
        'lastDocId': lastDocId,
      },
    );
  }

  Future<List<PrismWallpaper>?> _readCached() async {
    final snapshot = await _feedCacheLocal.read(source: 'prism', scope: 'main');
    if (snapshot == null || snapshot.payload is! Map) {
      return null;
    }

    final payload = _asMap(snapshot.payload);
    final rows = payload['rows'];
    if (rows is! List) {
      return null;
    }

    final mappedRows = rows
        .whereType<Map>()
        .map(_asMap)
        .map((entry) {
          final doc = _asMap(entry['doc']);
          final docId = entry['docId']?.toString() ?? '';
          if (docId.isEmpty || doc.isEmpty) {
            return null;
          }
          return _PrismRow(docId: docId, doc: PrismWallDocDto.fromJson(doc));
        })
        .whereType<_PrismRow>()
        .toList(growable: false);

    if (mappedRows.isEmpty) {
      return null;
    }

    _hasMore = payload['hasMore'] == true;
    final String? cachedLastDocId = payload['lastDocId']?.toString();
    if (cachedLastDocId != null && cachedLastDocId.isNotEmpty) {
      _lastDocId = cachedLastDocId;
    }

    final Set<String> blocked = await _blockedCreatorEmails(waitForInitialLoad: true);
    return mappedRows
        .map((row) => row.doc.toDomain(docId: row.docId))
        .where((w) => !BlockedCreatorsFilter.hidesCreatorEmail(w.core.authorEmail, blocked))
        .toList(growable: false);
  }

  Future<Set<String>> _blockedCreatorEmails({required bool waitForInitialLoad}) {
    return _userBlockRepository.getBlockedCreatorEmails(waitForInitialLoad: waitForInitialLoad);
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, dynamic>((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

class _PrismRow {
  const _PrismRow({required this.docId, required this.doc});

  final String docId;
  final PrismWallDocDto doc;
}
