import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';

class WallpaperDetailGallerySnapshot {
  const WallpaperDetailGallerySnapshot({required this.items, required this.index});

  final List<WallpaperDetailEntity> items;
  final int index;
}

class WallpaperDetailGalleryStore {
  WallpaperDetailGalleryStore._();

  static List<WallpaperDetailEntity> _items = const <WallpaperDetailEntity>[];
  static int _index = 0;

  static void setFromFeedItems({required List<FeedItemEntity> items, required int index}) {
    final entities = items.map(WallpaperDetailEntityX.fromFeedItem).toList(growable: false);
    setFromEntities(items: entities, index: index);
  }

  static void setFromEntities({required List<WallpaperDetailEntity> items, required int index}) {
    if (items.isEmpty) {
      _items = const <WallpaperDetailEntity>[];
      _index = 0;
      return;
    }
    _items = List<WallpaperDetailEntity>.unmodifiable(items);
    _index = index >= 0 && index < _items.length ? index : 0;
  }

  static WallpaperDetailGallerySnapshot? snapshotFor(WallpaperDetailEntity entity) {
    if (_items.isEmpty) return null;
    final matchedIndex = _items.indexWhere((candidate) => _isSameWallpaper(candidate, entity));
    if (matchedIndex < 0) return null;
    _index = matchedIndex;
    return WallpaperDetailGallerySnapshot(items: _items, index: matchedIndex);
  }

  static WallpaperDetailGallerySnapshot? current() {
    if (_items.isEmpty) return null;
    return WallpaperDetailGallerySnapshot(items: _items, index: _index);
  }

  static bool _isSameWallpaper(WallpaperDetailEntity a, WallpaperDetailEntity b) {
    final aId = a.id.trim().toLowerCase();
    final bId = b.id.trim().toLowerCase();
    if (a.source == b.source && aId.isNotEmpty && aId == bId) return true;
    final aUrl = a.fullUrl.trim().toLowerCase();
    final bUrl = b.fullUrl.trim().toLowerCase();
    return aUrl.isNotEmpty && aUrl == bUrl;
  }
}
