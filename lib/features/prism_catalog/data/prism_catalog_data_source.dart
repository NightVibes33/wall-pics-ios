import 'dart:async';
import 'dart:convert';

import 'package:Prism/core/wallpaper/wallpaper_core.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/env/env.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/category_feed_page.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class PrismCatalogDataSource {
  PrismCatalogDataSource._();

  static final PrismCatalogDataSource instance = PrismCatalogDataSource._();

  static const int _pageSize = 24;
  static const String regularContentType = 'regular_wallpaper';
  static const String liveContentType = 'live_wallpaper';
  static const String matchingContentType = 'matching_wallpaper';
  static const String doubleContentType = 'double_wallpaper';
  static const String parallaxContentType = 'parallax_wallpaper';
  static const String profilePictureContentType = 'profile_picture';
  static const String chargingAnimationContentType = 'charging_animation';
  static const String diyTemplateContentType = 'diy_template';
  static const String liveDiyTemplateContentType = 'live_diy_template';
  static const String stickerContentType = 'sticker';
  static const String aiFilterContentType = 'ai_filter';
  static const Map<String, String> _catalogFilesByContentType = <String, String>{
    regularContentType: 'prism_regular.json',
    liveContentType: 'prism_live.json',
    matchingContentType: 'prism_matching.json',
    doubleContentType: 'prism_double.json',
    parallaxContentType: 'prism_parallax.json',
    profilePictureContentType: 'prism_profile_pictures.json',
    chargingAnimationContentType: 'prism_charging_animations.json',
    diyTemplateContentType: 'prism_diy_templates.json',
    liveDiyTemplateContentType: 'prism_live_diy_templates.json',
    stickerContentType: 'prism_stickers.json',
    aiFilterContentType: 'prism_ai_filters.json',
  };
  static const Map<String, String> _contentTypeLabels = <String, String>{
    regularContentType: 'For You',
    liveContentType: 'Live Wallpapers',
    matchingContentType: 'Matching Wallpapers',
    doubleContentType: 'Double Wallpapers',
    parallaxContentType: '3D Spatial',
    profilePictureContentType: 'Profile Pictures',
    chargingAnimationContentType: 'Charging Animations',
    diyTemplateContentType: 'DIY Templates',
    liveDiyTemplateContentType: 'Live DIY Templates',
    stickerContentType: 'Stickers',
    aiFilterContentType: 'Filters',
  };
  static const Map<String, String> _sourceSectionContentTypes = <String, String>{
    'regular': regularContentType,
    'live': liveContentType,
    'matching': matchingContentType,
    'double': doubleContentType,
    'parallax': parallaxContentType,
    'profile_pictures': profilePictureContentType,
    'charging_animations': chargingAnimationContentType,
    'diy_templates': diyTemplateContentType,
    'live_diy_templates': liveDiyTemplateContentType,
    'stickers': stickerContentType,
    'ai_filters': aiFilterContentType,
  };
  static const Map<String, String> _numericCategoryTypes = <String, String>{
    '0': regularContentType,
    '1': liveContentType,
    '2': doubleContentType,
    '3': matchingContentType,
    '4': parallaxContentType,
  };

  final Map<String, Future<_PrismCatalog>> _catalogFutures = <String, Future<_PrismCatalog>>{};
  final Map<String, int> _offsets = <String, int>{};

  bool supports(CategoryEntity category) {
    final slug = category.catalogSlug?.trim();
    final type = category.catalogContentType?.trim();
    return slug != null && slug.isNotEmpty && type != null && _catalogFilesByContentType.containsKey(type);
  }

  Future<CategoryFeedPage?> fetchCategoryFeed({required CategoryEntity category, required bool refresh}) async {
    if (!supports(category)) return null;

    final catalog = await _catalogFor(category.catalogContentType!);
    final slug = category.catalogSlug!.trim();
    final scope = _scope(slug: slug, contentType: category.catalogContentType!);
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

  Future<List<CategoryEntity>> loadCategories() async {
    final categories = <CategoryEntity>[];
    final seen = <String>{};

    for (final entry in _contentTypeLabels.entries) {
      const preview = '';
      categories.add(
        CategoryEntity(
          name: entry.value,
          source: WallpaperSource.prism,
          searchType: CategorySearchType.nonSearch,
          image: preview,
          image2: preview,
          catalogSlug: 'for-you',
          catalogContentType: entry.key,
        ),
      );
      seen.add('${entry.key}:for-you');
    }

    final raw = await _loadCatalogJson('prism_category_trees.json');
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final rawCategories = payload['categories'];
    final rows = rawCategories is List ? rawCategories.whereType<Map>().map(_asMap).toList() : <Map<String, dynamic>>[];
    rows.sort((a, b) {
      final aParent = _string(a['parent_slug']).isEmpty ? 0 : 1;
      final bParent = _string(b['parent_slug']).isEmpty ? 0 : 1;
      final parentCompare = aParent.compareTo(bParent);
      if (parentCompare != 0) return parentCompare;
      final positionCompare = (_int(a['position']) ?? 999999).compareTo(_int(b['position']) ?? 999999);
      if (positionCompare != 0) return positionCompare;
      return _string(a['name']).compareTo(_string(b['name']));
    });

    for (final row in rows) {
      final name = _string(row['name']).trim();
      final slug = _string(row['slug']).trim();
      final contentType = _contentTypeForCategory(row);
      if (name.isEmpty || slug.isEmpty || !_catalogFilesByContentType.containsKey(contentType)) {
        continue;
      }
      final key = '$contentType:$slug';
      if (!seen.add(key)) {
        continue;
      }
      final preview = _string(row['preview_image']).trim();
      categories.add(
        CategoryEntity(
          name: name,
          source: WallpaperSource.prism,
          searchType: CategorySearchType.nonSearch,
          image: preview,
          image2: preview,
          catalogSlug: slug,
          catalogContentType: contentType,
        ),
      );
    }
    return categories;
  }

  Future<List<String>> popularSearches({int limit = 80}) async {
    final seen = <String>{};
    final searches = <String>[];
    final popularRows = <String>[];

    void add(String value) {
      if (searches.length >= limit) {
        return;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) {
        return;
      }
      searches.add(trimmed);
    }

    try {
      final raw = await _loadCatalogJson('prism_popular_searches.json');
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final rawItems = payload['wallpapers'];
      if (rawItems is List) {
        for (final row in rawItems.whereType<Map>().map(_asMap)) {
          final query = _string(row['query']).trim();
          if (query.isNotEmpty) {
            popularRows.add(query);
          }
        }
      }
    } catch (_) {
      // Search can still fall back to category names when remote metadata is unavailable.
    }

    final popularLeadLimit = limit < 40 ? limit : 40;
    for (final query in popularRows.take(popularLeadLimit)) {
      add(query);
    }

    try {
      final raw = await _loadCatalogJson('prism_search_suggestions.json');
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final rawSuggestions = payload['suggestions'];
      if (rawSuggestions is List) {
        for (final suggestion in rawSuggestions) {
          add(_string(suggestion));
        }
      }
      final rawQueries = payload['queries'];
      if (rawQueries is List) {
        for (final row in rawQueries.whereType<Map>().map(_asMap)) {
          final suggestions = row['suggestions'];
          if (suggestions is List) {
            for (final suggestion in suggestions) {
              add(_string(suggestion));
            }
          }
        }
      }
    } catch (_) {
      // Optional search suggestion metadata is remote-only.
    }

    for (final query in popularRows.skip(popularLeadLimit)) {
      add(query);
    }
    return searches;
  }

  Future<CategoryFeedPage> search({required String query, required bool refresh}) async {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty) {
      return const CategoryFeedPage(items: <FeedItemEntity>[], hasMore: false, nextCursor: null);
    }

    final scope = 'search.$normalizedQuery';
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final ranked = <_RankedPrismItem>[];
    for (final contentType in _catalogFilesByContentType.keys) {
      final catalog = await _catalogFor(contentType);
      for (final item in catalog.items) {
        final score = _scoreSearchMatch(item, normalizedQuery);
        if (score > 0) {
          ranked.add(_RankedPrismItem(item: item, score: score));
        }
      }
    }
    ranked.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final aCreated = a.item.createdAt?.millisecondsSinceEpoch ?? 0;
      final bCreated = b.item.createdAt?.millisecondsSinceEpoch ?? 0;
      return bCreated.compareTo(aCreated);
    });

    final deduped = _dedupeItems(ranked.map((entry) => entry.item));
    final page = deduped.skip(start).take(_pageSize).toList(growable: false);
    _offsets[scope] = start + page.length;

    return CategoryFeedPage(
      items: page.map((item) => PrismFeedItem(id: item.id, wallpaper: item.toWallpaper())).toList(growable: false),
      hasMore: start + page.length < deduped.length,
      nextCursor: (start + page.length).toString(),
    );
  }

  Future<PrismWallpaper?> fetchById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    for (final contentType in _catalogFilesByContentType.keys) {
      final item = (await _catalogFor(contentType)).byId(trimmed);
      if (item != null) return item.toWallpaper();
    }
    return null;
  }

  Future<_PrismCatalog> _catalogFor(String contentType) {
    final fileName = _catalogFilesByContentType[contentType] ?? _catalogFilesByContentType[regularContentType]!;
    return _catalogFutures[contentType] ??= _loadCatalog(fileName, contentType);
  }

  Future<_PrismCatalog> _loadRegular() => _catalogFor(regularContentType);

  Future<_PrismCatalog> _loadLive() => _catalogFor(liveContentType);

  Future<_PrismCatalog> _loadCatalog(String fileName, String fallbackType) async {
    final raw = await _loadCatalogJson(fileName);
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final contentType = payload['content_type']?.toString() ?? fallbackType;
    final rawItems = payload['wallpapers'];
    final items = rawItems is List
        ? _dedupeItems(rawItems.whereType<Map>().map((item) => _PrismItem.fromJson(_asMap(item), contentType)))
        : <_PrismItem>[];
    return _PrismCatalog(items);
  }


  String get _remoteCatalogBaseUrl {
    final configured = Env.normalize(Env.prismCatalogBaseUrl);
    if (configured.isNotEmpty) {
      return configured;
    }
    final apiBase = Env.normalize(Env.userStoreApiBaseUrl);
    if (apiBase.isEmpty) {
      return '';
    }
    final trimmed = apiBase.endsWith('/') ? apiBase.substring(0, apiBase.length - 1) : apiBase;
    return '$trimmed/v1/catalog';
  }

  Future<String> _loadCatalogJson(String fileName) async {
    final remoteBase = _remoteCatalogBaseUrl;
    if (remoteBase.isNotEmpty) {
      final base = remoteBase.endsWith('/') ? remoteBase.substring(0, remoteBase.length - 1) : remoteBase;
      try {
        final response = await http.get(Uri.parse('$base/$fileName')).timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300 && _looksLikeJson(response.body)) {
          return response.body;
        }
      } catch (_) {
        // Bundled metadata remains the offline fallback. Large catalogs are remote-only.
      }
    }

    try {
      return await rootBundle.loadString('assets/catalog/$fileName');
    } catch (_) {
      final contentType = _contentTypeForCatalogFile(fileName);
      if (contentType != null) {
        return jsonEncode(<String, Object?>{
          'content_type': contentType,
          'wallpapers': <Object?>[],
        });
      }
      if (fileName == 'prism_category_trees.json' || fileName == 'prism_categories.json') {
        return jsonEncode(<String, Object?>{'categories': <Object?>[]});
      }
      if (fileName == 'prism_popular_searches.json') {
        return jsonEncode(<String, Object?>{
          'content_type': 'popular_search',
          'wallpapers': <Object?>[],
        });
      }
      if (fileName == 'prism_search_suggestions.json') {
        return jsonEncode(<String, Object?>{
          'content_type': 'search_suggestion',
          'queries': <Object?>[],
          'suggestions': <Object?>[],
        });
      }
      if (fileName == 'prism_index.json') {
        return jsonEncode(<String, Object?>{'sections': <Object?>[]});
      }
      rethrow;
    }
  }

  bool _looksLikeJson(String body) {
    final trimmed = body.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  String _scope({required String slug, required String contentType}) => '$contentType.$slug';

  String? _contentTypeForCatalogFile(String fileName) {
    for (final entry in _catalogFilesByContentType.entries) {
      if (entry.value == fileName) {
        return entry.key;
      }
    }
    return null;
  }

  String _contentTypeForCategory(Map<String, dynamic> row) {
    final sourceSections = row['source_sections'];
    if (sourceSections is List) {
      for (final source in sourceSections) {
        final contentType = _sourceSectionContentTypes[_string(source)];
        if (contentType != null) {
          return contentType;
        }
      }
    }
    final type = _string(row['type']).trim();
    if (_catalogFilesByContentType.containsKey(type)) {
      return type;
    }
    return _numericCategoryTypes[type] ?? regularContentType;
  }
}

class _PrismCatalog {
  _PrismCatalog(this.items) : _byId = <String, _PrismItem>{for (final item in items) item.id: item};

  final List<_PrismItem> items;
  final Map<String, _PrismItem> _byId;

  List<_PrismItem> itemsForSlug(String slug) {
    if (slug == 'for-you') return items;
    return items.where((item) => item.categorySlugs.contains(slug)).toList(growable: false);
  }

  _PrismItem? byId(String id) => _byId[id];

  String get firstPreviewUrl {
    for (final item in items) {
      final preview = item.previewUrl.trim().isNotEmpty ? item.previewUrl : item.thumbnailUrl;
      if (preview.trim().isNotEmpty) {
        return preview;
      }
    }
    return '';
  }
}

class _RankedPrismItem {
  const _RankedPrismItem({required this.item, required this.score});

  final _PrismItem item;
  final int score;
}

class _PrismItem {
  const _PrismItem({
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
    required this.pairedWallpapers,
    required this.pairedPreviewUrls,
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
  final List<Map<String, dynamic>> pairedWallpapers;
  final List<String> pairedPreviewUrls;
  final String? authorName;
  final String? authorId;
  final DateTime? createdAt;
  final bool isPremium;
  final List<String> categoryNames;
  final List<String> categorySlugs;
  final List<String> tags;

  bool get isLive => contentType == PrismCatalogDataSource.liveContentType;

  factory _PrismItem.fromJson(Map<String, dynamic> json, String contentType) {
    final categories = _maps(json['categories']);
    final tagRows = _maps(json['tags']);
    final author = _asMap(json['author_data']);
    final wallpaper = _string(json['wallpaper']);
    final catalogDownload = _string(json['download_url']);
    final pairedWallpapers = _maps(json['paired_wallpapers']);
    final pairedPreviewUrls = _strings(json['paired_preview_urls']);
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
      json['image'],
      json['template'],
      json['sticker'],
      json['parallax_file'],
      video,
    ]);
    final staticThumb = _firstString(<Object?>[
      json['static_thumbnail'],
      json['hq_thumbnail'],
      json['first_frame_thumbnail'],
      thumb,
    ]);
    final preview = _firstString(<Object?>[
      json['preview_image'],
      json['hq_thumbnail'],
      json['static_thumbnail'],
      json['first_frame_thumbnail'],
      json['thumbnail'],
      wallpaper,
      json['image'],
      json['template'],
      json['sticker'],
      json['parallax_file'],
      video,
    ]);
    return _PrismItem(
      id: _string(json['id']),
      name: _string(json['name']),
      slug: _string(json['slug']),
      description: _string(json['description']),
      contentType: contentType,
      width: _int(json['width']),
      height: _int(json['height']),
      downloadUrl: contentType == PrismCatalogDataSource.liveContentType
          ? _firstString(<Object?>[catalogDownload, video, wallpaper])
          : _firstString(<Object?>[catalogDownload, wallpaper, video]),
      previewUrl: preview,
      thumbnailUrl: thumb,
      staticThumbnailUrl: staticThumb,
      videoUrl: video,
      thumbnailVideoUrl: _string(json['thumbnail_video']),
      pairedWallpapers: pairedWallpapers,
      pairedPreviewUrls: pairedPreviewUrls,
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
        authorName: null,
        authorId: null,
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
        'catalogContentType': contentType,
        'catalogSlug': slug,
        'catalogDescription': description,
        'catalogPreviewUrl': previewUrl,
        'catalogStaticThumbnailUrl': staticThumbnailUrl,
        'catalogVideoUrl': videoUrl,
        'catalogThumbnailVideoUrl': thumbnailVideoUrl,
        'catalogPairedWallpapers': pairedWallpapers,
        'catalogPairedPreviewUrls': pairedPreviewUrls,
        'catalogIsPremium': isPremium,
      },
      remoteStoreDocumentId: 'prism-$id',
    );
  }
}

List<_PrismItem> _dedupeItems(Iterable<_PrismItem> items) {
  final seenIds = <String>{};
  final seenUrls = <String>{};
  final deduped = <_PrismItem>[];
  for (final item in items) {
    final idKey = item.id.trim().isEmpty ? '' : '${item.contentType}:${item.id.trim()}';
    final urlKey = _firstString(<Object?>[item.downloadUrl, item.previewUrl, item.thumbnailUrl]).trim().toLowerCase();
    if (idKey.isNotEmpty && !seenIds.add(idKey)) {
      continue;
    }
    if (urlKey.isNotEmpty && !seenUrls.add(urlKey)) {
      continue;
    }
    if (item.id.trim().isEmpty && urlKey.isEmpty) {
      continue;
    }
    deduped.add(item);
  }
  return deduped;
}

String _normalizeForSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

int _scoreSearchMatch(_PrismItem item, String normalizedQuery) {
  final tokens = normalizedQuery.split(' ').where((token) => token.isNotEmpty).toList(growable: false);
  if (tokens.isEmpty) {
    return 0;
  }

  final name = _normalizeForSearch(item.name);
  final slug = _normalizeForSearch(item.slug);
  final description = _normalizeForSearch(item.description);
  final categories = item.categoryNames.map(_normalizeForSearch).where((value) => value.isNotEmpty).toList();
  final categorySlugs = item.categorySlugs.map(_normalizeForSearch).where((value) => value.isNotEmpty).toList();
  final tags = item.tags.map(_normalizeForSearch).where((value) => value.isNotEmpty).toList();
  final fields = <String>[name, slug, description, ...categories, ...categorySlugs, ...tags];
  final haystack = fields.join(' ');

  if (name == normalizedQuery || slug == normalizedQuery) {
    return 10000;
  }
  if (categories.any((value) => value == normalizedQuery) || categorySlugs.any((value) => value == normalizedQuery)) {
    return 9000;
  }
  if (tags.any((value) => value == normalizedQuery)) {
    return 8000;
  }
  if (name.startsWith(normalizedQuery) || slug.startsWith(normalizedQuery)) {
    return 7000;
  }
  if (categories.any((value) => value.startsWith(normalizedQuery)) ||
      categorySlugs.any((value) => value.startsWith(normalizedQuery)) ||
      tags.any((value) => value.startsWith(normalizedQuery))) {
    return 6000;
  }
  if (name.contains(normalizedQuery) || slug.contains(normalizedQuery)) {
    return 5000;
  }
  if (fields.any((value) => value.contains(normalizedQuery))) {
    return 4000;
  }

  final matchingTokens = tokens.where((token) => haystack.contains(token)).length;
  if (matchingTokens == tokens.length) {
    return 2500 + matchingTokens;
  }
  return 0;
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

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return value.map(_string).where((text) => text.trim().isNotEmpty).toList(growable: false);
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
