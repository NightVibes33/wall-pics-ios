import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/prism_feed/domain/repositories/prism_wallpaper_repository.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/logger/logger.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: PrismWallpaperRepository)
class PrismWallpaperRepositoryImpl implements PrismWallpaperRepository {
  PrismWallpaperRepositoryImpl(Object? _, Object? __, Object? ___);

  bool _hasMore = true;

  @override
  bool get hasMore => _hasMore;

  @override
  Future<Result<List<PrismWallpaper>>> fetchFeed({required bool refresh}) async {
    try {
      final catalogPage = await PrismCatalogDataSource.instance.fetchHomePage(refresh: refresh);
      _hasMore = catalogPage.hasMore;
      final walls = catalogPage.items
          .whereType<PrismFeedItem>()
          .map((item) => item.wallpaper)
          .toList(growable: false);
      logger.i('[PrismWallpaperRepository] Prism feed loaded', fields: <String, Object?>{'count': walls.length});
      return Result.success(walls);
    } catch (error, stackTrace) {
      _hasMore = false;
      logger.e('[PrismWallpaperRepository] Prism feed failed', error: error, stackTrace: stackTrace);
      return Result.error(ServerFailure('Failed to fetch Prism feed: $error'));
    }
  }

  @override
  Future<Result<List<PrismWallpaper>>> fetchStreakShopWallpapers() async {
    _hasMore = false;
    return Result.success(<PrismWallpaper>[]);
  }

  @override
  Future<Result<PrismWallpaper?>> fetchById(String id) async {
    try {
      return Result.success(await PrismCatalogDataSource.instance.fetchById(id));
    } catch (error, stackTrace) {
      logger.e('[PrismWallpaperRepository] Prism fetchById failed', error: error, stackTrace: stackTrace);
      return Result.error(ServerFailure('Failed to fetch Prism wallpaper by id: $error'));
    }
  }

  @override
  Future<Result<PrismWallpaper?>> fetchByDocumentId(String documentId) async {
    return Result.success(null);
  }
}
