import 'dart:async';
import 'dart:convert';

import 'package:Prism/core/wallpaper/wallpaper_core.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/category_feed_page.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class WallpicsCatalogDataSource {
  WallpicsCatalogDataSource._();

  static final WallpicsCatalogDataSource instance = WallpicsCatalogDataSource._();

  static const int _pageSize = 24;
  static const String regularContentType = 'regular_wallpaper';
  static const String liveContentType = 'live_wallpaper';
  static const String _remoteCatalogBaseUrl = String.fromEnvironment('WALL_PICS_CATALOG_BASE_URL');

  Future<_WallpicsCatalog>? _regularFuture;
  Future<_WallpicsCatalog>? _liveFuture;
  final Map<String, int> _offsets = <String, int>{};

  bool supports(CategoryEntity category) {
    final slug = category.wallpicsSlug?.trim();
    final type = category.wallpicsContentType?.trim();
    return slug != null && slug.isNotEmpty && (type == regularContentType || type == liveContentType);
  }

  Future<CategoryFeedPage?> fetchCategoryFeed({required CategoryEntity category, required bool refresh}) async {
    if (!supports(category)) return null;

    final catalog = await _catalogFor(category.wallpicsContentType!);
    final slug = category.wallpicsSlug!.trim();
    final scope = _scope(slug: slug, contentType: category.wallpicsContentType!);
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final matches = catalog.itemsForSlug(slug);
    final page = matches.skip(start).take(_pageSize).toList(growable: false);
    _offsets[scope] = start + page.length;

    return CategoryFeedPage(
      items: page.map((item) => PrismFeedItem(id: item.id, wallpaper: item.toWallpaper())).toList(growable: false),
      hasMore: start + page.length < matches.length,
      nextCursor: (start + page.length).toString(),
    );
  }

  Future<CategoryFeedPage> fetchHomePage({required bool refresh}) async {
    final catalog = await _loadRegular();
    final scope = _scope(slug: 'for-you', contentType: regularContentType);
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final matches = catalog.itemsForSlug('for-you');
    final page = matches.skip(start).take(_pageSize).toList(growable: false);
    _offsets[scope] = start + page.length;
    return CategoryFeedPage(
      items: page.map((item) => PrismFeedItem(id: item.id, wallpaper: item.toWallpaper())).toList(growable: false),
      hasMore: start + page.length < matches.length,
      nextCursor: (start + page.length).toString(),
    );
  }

  Future<PrismWallpaper?> fetchById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    for (final catalog in <_WallpicsCatalog>[await _loadRegular(), await _loadLive()]) {
      final item = catalog.byId(trimmed);
      if (item != null) return item.toWallpaper();
    }
    return null;
  }

  Future<_WallpicsCatalog> _catalogFor(String contentType) {
    if (contentType == liveContentType) return _loadLive();
    return _loadRegular();
  }

  Future<_WallpicsCatalog> _loadRegular() {
    return _regularFuture ??= _loadCatalog('wallpics_regular.json', regularContentType);
  }

  Future<_WallpicsCatalog> _loadLive() {
    return _liveFuture ??= _loadCatalog('wallpics_live.json', liveContentType);
  }

  Future<_WallpicsCatalog> _loadCatalog(String fileName, String fallbackType) async {
    final raw = await _loadCatalogJson(fileName);
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final contentType = payload['content_type']?.toString() ?? fallbackType;
    final rawItems = payload['wallpapers'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((item) => _WallpicsItem.fromJson(_asMap(item), contentType)).toList()
        : <_WallpicsItem>[];
    return _WallpicsCatalog(items);
  }

  Future<String> _loadCatalogJson(String fileName) async {
    final remoteBase = _remoteCatalogBaseUrl.trim();
    if (remoteBase.isNotEmpty) {
      final base = remoteBase.endsWith('/') ? remoteBase.substring(0, remoteBase.length - 1) : remoteBase;
      try {
        final response = await http.get(Uri.parse('$base/$fileName')).timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300 && response.body.trim().isNotEmpty) {
          return response.body;
        }
      } catch (_) {
        // Bundled catalog remains the offline fallback.
      }
    }
    return rootBundle.loadString('assets/catalog/$fileName');
  }

  String _scope({required String slug, required String contentType}) => '$contentType.$slug';
}

class _WallpicsCatalog {
  _WallpicsCatalog(this.items) : _byId = <String, _WallpicsItem>{for (final item in items) item.id: item};

  final List<_WallpicsItem> items;
  final Map<String, _WallpicsItem> _byId;

  List<_WallpicsItem> itemsForSlug(String slug) {
    if (slug == 'for-you') return items;
    return items.where((item) => item.categorySlugs.contains(slug)).toList(growable: false);
  }

  _WallpicsItem? byId(String id) => _byId[id];
}

class _WallpicsItem {
  const _WallpicsItem({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.contentType,
    required this.width,
    required this.height,
    required this.downloadUrl,
    required this.previewUrl,
    required this.thumbnailUrl,
    required this.staticThumbnailUrl,
    required this.videoUrl,
    required this.thumbnailVideoUrl,
    required this.authorName,
    required this.authorId,
    required this.createdAt,
    required this.isPremium,
    required this.categoryNames,
    required this.categorySlugs,
    required this.tags,
  });

  final String id;
  final String name;
  final String slug;
  final String description;
  final String contentType;
  final int? width;
  final int? height;
  final String downloadUrl;
  final String previewUrl;
  final String thumbnailUrl;
  final String staticThumbnailUrl;
  final String videoUrl;
  final String thumbnailVideoUrl;
  final String? authorName;
  final String? authorId;
  final DateTime? createdAt;
  final bool isPremium;
  final List<String> categoryNames;
  final List<String> categorySlugs;
  final List<String> tags;

  bool get isLive => contentType == WallpicsCatalogDataSource.liveContentType;

  factory _WallpicsItem.fromJson(Map<String, dynamic> json, String contentType) {
    final categories = _maps(json['categories']);
    final tagRows = _maps(json['tags']);
    final author = _asMap(json['author_data']);
    final wallpaper = _string(json['wallpaper']);
    final video = _firstString(<Object?>[
      json['video_original '],
      json['video_original'],
      json['video'],
      json['lq_video'],
      json['android_video'],
    ]);
    final thumb = _firstString(<Object?>[
      json['thumbnail'],
      json['static_thumbnail'],
      json['hq_thumbnail'],
      json['first_frame_thumbnail'],
      wallpaper,
      video,
    ]);
    final staticThumb = _firstString(<Object?>[
      json['static_thumbnail'],
      json['hq_thumbnail'],
      json['first_frame_thumbnail'],
      thumb,
    ]);
    final preview = _firstString(<Object?>[
      json['hq_thumbnail'],
      json['static_thumbnail'],
      json['first_frame_thumbnail'],
      json['thumbnail'],
      wallpaper,
    ]);
    return _WallpicsItem(
      id: _string(json['id']),
      name: _string(json['name']),
      slug: _string(json['slug']),
      description: _string(json['description']),
      contentType: contentType,
      width: _int(json['width']),
      height: _int(json['height']),
      downloadUrl: contentType == WallpicsCatalogDataSource.liveContentType ? video : wallpaper,
      previewUrl: preview,
      thumbnailUrl: thumb,
      staticThumbnailUrl: staticThumb,
      videoUrl: video,
      thumbnailVideoUrl: _string(json['thumbnail_video']),
      authorName: _firstString(<Object?>[author['name'], json['author']]).trim().isEmpty
          ? null
          : _firstString(<Object?>[author['name'], json['author']]),
      authorId: _string(author['id']).isEmpty ? null : _string(author['id']),
      createdAt: DateTime.tryParse(_string(json['created_at']))?.toUtc(),
      isPremium: _int(json['is_premium']) == 1,
      categoryNames: categories.map((category) => _string(category['name'])).where((name) => name.isNotEmpty).toList(),
      categorySlugs: categories.map((category) => _string(category['slug'])).where((slug) => slug.isNotEmpty).toList(),
      tags: tagRows.map((tag) => _string(tag['name'])).where((tag) => tag.isNotEmpty).toList(),
    );
  }

  PrismWallpaper toWallpaper() {
    final String full = downloadUrl.isNotEmpty ? downloadUrl : previewUrl;
    final String thumb = thumbnailUrl.isNotEmpty ? thumbnailUrl : previewUrl;
    return PrismWallpaper(
      core: WallpaperCore(
        id: id,
        source: WallpaperSource.prism,
        fullUrl: full,
        thumbnailUrl: thumb,
        resolution: width != null && height != null ? '${width}x$height' : null,
        authorName: authorName,
        authorId: authorId,
        category: categoryNames.isNotEmpty ? categoryNames.first : null,
        createdAt: createdAt,
        width: width,
        height: height,
        favourites: null,
      ),
      collections: categoryNames,
      review: true,
      tags: tags,
      aiMetadata: <String, Object?>{
        'wallpicsContentType': contentType,
        'wallpicsSlug': slug,
        'wallpicsDescription': description,
        'wallpicsPreviewUrl': previewUrl,
        'wallpicsStaticThumbnailUrl': staticThumbnailUrl,
        'wallpicsVideoUrl': videoUrl,
        'wallpicsThumbnailVideoUrl': thumbnailVideoUrl,
        'wallpicsIsPremium': isPremium,
      },
      remoteStoreDocumentId: 'wallpics-$id',
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map<String, dynamic>((key, val) => MapEntry(key.toString(), val));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.whereType<Map>().map(_asMap).toList(growable: false);
}

String _string(Object? value) => value?.toString() ?? '';

String _firstString(List<Object?> values) {
  for (final value in values) {
    final text = _string(value).trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(_string(value));
}
