import 'dart:async';
import 'dart:convert';

import 'package:Prism/core/persistence/persistence_keys.dart';
import 'package:Prism/core/persistence/store_adapters/lazy_file_cache.dart';
import 'package:Prism/core/wallpaper/wallpaper_core.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/env/env.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/category_feed_page.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

class PrismCatalogDataSource {
  PrismCatalogDataSource._();

  static final PrismCatalogDataSource instance = PrismCatalogDataSource._();

  static String fastImageTileUrl(String url, {int width = 1080, int quality = 90}) {
    return _fastTileImageUrl(url, width: width, quality: quality);
  }

  static String fastImageFullUrl(String url, {int width = 3840, int quality = 98}) {
    return _fastTileImageUrl(url, width: width, quality: quality);
  }

  static String fastVideoUrl(String url) {
    return _fastVideoUrl(url);
  }

  static const int _pageSize = 144;
  static const int _catalogShardSize = 100;
  static const Duration _metadataTimeout = Duration(seconds: 10);
  static const Duration _pageTimeout = Duration(seconds: 8);
  static const Duration _searchIndexTimeout = Duration(seconds: 20);
  static const Duration _bootstrapTimeout = Duration(seconds: 4);
  static const String _homeBootstrapFile = 'prism_bootstrap_home.json';
  static const int _bootstrapPrefetchLimit = 360;
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
  static const Set<String> _hiddenContentTypes = <String>{
    chargingAnimationContentType,
    diyTemplateContentType,
    liveDiyTemplateContentType,
    stickerContentType,
  };
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
  };
  static const Map<String, String> _catalogPagePrefixesByContentType = <String, String>{
    regularContentType: 'prism_regular',
    liveContentType: 'prism_live',
    matchingContentType: 'prism_matching',
    doubleContentType: 'prism_double',
    parallaxContentType: 'prism_parallax',
    profilePictureContentType: 'prism_profile_pictures',
    chargingAnimationContentType: 'prism_charging_animations',
    diyTemplateContentType: 'prism_diy_templates',
    liveDiyTemplateContentType: 'prism_live_diy_templates',
    stickerContentType: 'prism_stickers',
  };
  static const Map<String, String> _contentTypeLabels = <String, String>{
    regularContentType: 'For You',
    liveContentType: 'Live Photos',
    matchingContentType: 'Matching Sets',
    doubleContentType: 'Wallpaper Pairs',
    parallaxContentType: 'Spatial Wallpapers',
    profilePictureContentType: 'Profile Pictures',
    chargingAnimationContentType: 'Charging Animations',
    diyTemplateContentType: 'DIY Templates',
    liveDiyTemplateContentType: 'Live DIY Templates',
    stickerContentType: 'Stickers',
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
  };
  static const Map<String, String> _numericCategoryTypes = <String, String>{
    '0': regularContentType,
    '1': liveContentType,
    '2': doubleContentType,
    '3': matchingContentType,
    '4': parallaxContentType,
  };
  static const Map<String, String> _directApiEndpointsByContentType = <String, String>{
    regularContentType: '/api/wallpaper-list',
    liveContentType: '/api/wallpapers/live',
    matchingContentType: '/api/wallpapers/matching',
    doubleContentType: '/api/wallpapers/double',
    parallaxContentType: '/api/wallpapers/parallax',
    profilePictureContentType: '/api/profile-pictures',
  };
  static const Map<String, String> _directApiSectionsByContentType = <String, String>{
    regularContentType: 'regular',
    liveContentType: 'live',
    matchingContentType: 'matching',
    doubleContentType: 'double',
    parallaxContentType: 'parallax',
    profilePictureContentType: 'profile_pictures',
  };

  final LazyFileCache _catalogCache = LazyFileCache('prism_catalog_cache');
  final Map<String, Future<_PrismCatalogPage>> _pageFutures = <String, Future<_PrismCatalogPage>>{};
  final Map<String, Future<_PrismCatalogPage?>> _directApiPageFutures = <String, Future<_PrismCatalogPage?>>{};
  final Map<String, Future<List<_PrismItem>>> _compactCatalogFutures = <String, Future<List<_PrismItem>>>{};
  final Map<String, Future<CategoryFeedPage?>> _fullCategoryFeedFutures = <String, Future<CategoryFeedPage?>>{};
  final Map<String, Future<CategoryFeedPage>> _searchAllFutures = <String, Future<CategoryFeedPage>>{};
  final Map<String, int> _offsets = <String, int>{};
  Future<List<Map<String, dynamic>>>? _categoryRowsFuture;
  Future<Map<String, Map<String, List<String>>>>? _categoryIdsFuture;
  Future<Map<String, Map<String, int>>>? _itemLocationsFuture;
  Future<List<_SearchIndexEntry>>? _searchIndexFuture;

  bool supports(CategoryEntity category) {
    final slug = category.catalogSlug?.trim();
    final type = category.catalogContentType?.trim();
    return slug != null &&
        slug.isNotEmpty &&
        type != null &&
        !_hiddenContentTypes.contains(type) &&
        _catalogPagePrefixesByContentType.containsKey(type);
  }

  Future<CategoryFeedPage?> fetchCategoryFeed({required CategoryEntity category, required bool refresh}) async {
    if (!supports(category)) return null;

    final contentType = category.catalogContentType!.trim();
    final slug = category.catalogSlug!.trim();
    final scope = _scope(slug: slug, contentType: contentType);

    if (slug == 'for-you') {
      final directFeed = await _fetchDirectApiPageFeed(
        contentType: contentType,
        slug: slug,
        scope: scope,
        refresh: refresh,
      );
      if (directFeed != null) {
        return directFeed;
      }
      return _fetchSequentialPageFeed(contentType: contentType, scope: scope, refresh: refresh);
    }
    if (slug == 'newest' || slug == 'new') {
      return _fetchNewestPageFeed(contentType: contentType, scope: scope, refresh: refresh);
    }

    final directFeed = await _fetchDirectApiPageFeed(
      contentType: contentType,
      slug: slug,
      scope: scope,
      refresh: refresh,
    );
    if (directFeed != null) {
      return directFeed;
    }

    final categoryIds = await _categoryIdsFor(contentType, slug);
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final pageIds = categoryIds.skip(start).take(_pageSize).toList(growable: false);
    final items = await _itemsByIds(contentType: contentType, ids: pageIds);
    final nextOffset = start + pageIds.length;
    _offsets[scope] = nextOffset;

    return _toFeedPage(
      items,
      hasMore: nextOffset < categoryIds.length,
      nextOffset: nextOffset,
    );
  }

  Future<CategoryFeedPage?> fetchFullCategoryFeed({required CategoryEntity category}) {
    if (!supports(category)) return Future<CategoryFeedPage?>.value(null);

    final contentType = category.catalogContentType!.trim();
    final slug = category.catalogSlug!.trim();
    final scope = _scope(slug: slug, contentType: contentType);
    final cached = _fullCategoryFeedFutures[scope];
    if (cached != null) return cached;

    final future = _fetchFullCategoryFeedInternal(contentType: contentType, slug: slug);
    _fullCategoryFeedFutures[scope] = future;
    unawaited(
      future.catchError((Object _) {
        _fullCategoryFeedFutures.remove(scope);
        return null;
      }),
    );
    return future;
  }

  Future<CategoryFeedPage?> _fetchFullCategoryFeedInternal({required String contentType, required String slug}) async {
    final items = <_PrismItem>[];
    if (slug == 'for-you') {
      var pageNumber = 1;
      var guard = 0;
      while (guard < 500) {
        guard += 1;
        final catalogPage = await _loadCatalogPage(contentType, pageNumber);
        if (catalogPage.items.isEmpty) break;
        items.addAll(catalogPage.items);
        if (!catalogPage.hasMore || items.length >= catalogPage.itemCount) break;
        pageNumber += 1;
      }
      return _toFeedPage(_dedupeItems(items), hasMore: false, nextOffset: items.length);
    }

    if (slug == 'newest' || slug == 'new') {
      final searchIndex = await _loadSearchIndex();
      final refs = <_RankedItemReference>[];
      for (var index = 0; index < searchIndex.length; index++) {
        final entry = searchIndex[index];
        if (entry.contentType != contentType ||
            entry.createdAt == null ||
            !_catalogPagePrefixesByContentType.containsKey(entry.contentType) ||
            _hiddenContentTypes.contains(entry.contentType)) {
          continue;
        }
        refs.add(
          _RankedItemReference(
            contentType: entry.contentType,
            id: entry.id,
            page: entry.page,
            score: 0,
            ordinal: index,
            createdAt: entry.createdAt,
          ),
        );
      }
      refs.sort(_compareNewestReferences);
      final newestItems = await _itemsByReferences(_dedupeReferences(refs));
      return _toFeedPage(newestItems, hasMore: false, nextOffset: newestItems.length);
    }

    final categoryIds = await _categoryIdsFor(contentType, slug);
    final categoryItems = await _itemsByIds(contentType: contentType, ids: categoryIds);
    return _toFeedPage(_dedupeItems(categoryItems), hasMore: false, nextOffset: categoryItems.length);
  }

  Future<CategoryFeedPage> fetchHomePage({required bool refresh}) {
    return _fetchSequentialPageFeed(
      contentType: regularContentType,
      scope: _scope(slug: 'for-you', contentType: regularContentType),
      refresh: refresh,
    );
  }

  Future<PrismCatalogHomeBootstrap?> fetchHomeBootstrap({bool refresh = false}) async {
    try {
      final raw = await _loadCatalogJson(
        _homeBootstrapFile,
        timeout: _bootstrapTimeout,
        allowGeneratedFallback: false,
        preferCache: !refresh,
      );
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      return PrismCatalogHomeBootstrap.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

  Future<void> warmCatalogCache({bool prefetchMedia = true}) async {
    await Future.wait<void>(<Future<void>>[
      warmHomeBootstrapCache(prefetchMedia: prefetchMedia),
      _warmCatalogJsonFiles(),
    ]);
  }

  Future<void> warmHomeBootstrapCache({bool prefetchMedia = true}) async {
    final bootstrap = await fetchHomeBootstrap(refresh: true);
    if (bootstrap == null || !prefetchMedia) {
      return;
    }
    final seenUrls = <String>{};
    final urls = <String>[];
    void addPrefetchUrl(String rawUrl) {
      if (urls.length >= _bootstrapPrefetchLimit) {
        return;
      }
      final url = rawUrl.trim();
      if (url.isEmpty || !_isFastPrefetchableUrl(url) || !seenUrls.add(url)) {
        return;
      }
      urls.add(url);
    }

    for (final section in bootstrap.sections) {
      for (final item in section.items) {
        addPrefetchUrl(item.thumbnailUrl);
      }
    }
    for (final rawUrl in bootstrap.prefetchUrls) {
      addPrefetchUrl(_fastTileImageUrl(rawUrl));
    }
    const batchSize = 12;
    for (var index = 0; index < urls.length; index += batchSize) {
      final batch = urls.skip(index).take(batchSize);
      unawaited(
        Future.wait<void>(
          batch.map((url) async {
            try {
              await DefaultCacheManager().downloadFile(url).timeout(const Duration(seconds: 6));
            } catch (_) {
              // Prefetch failures should not block startup or catalog rendering.
            }
          }),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<CategoryFeedPage> _fetchNewestPageFeed({
    required String contentType,
    required String scope,
    required bool refresh,
  }) async {
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final searchIndex = await _loadSearchIndex();
    final refs = <_RankedItemReference>[];
    for (var index = 0; index < searchIndex.length; index++) {
      final entry = searchIndex[index];
      if (entry.contentType != contentType ||
          entry.createdAt == null ||
          !_catalogPagePrefixesByContentType.containsKey(entry.contentType) ||
          _hiddenContentTypes.contains(entry.contentType)) {
        continue;
      }
      refs.add(
        _RankedItemReference(
          contentType: entry.contentType,
          id: entry.id,
          page: entry.page,
          score: 0,
          ordinal: index,
          createdAt: entry.createdAt,
        ),
      );
    }
    refs.sort(_compareNewestReferences);
    final deduped = _dedupeReferences(refs);
    final pageRefs = deduped.skip(start).take(_pageSize).toList(growable: false);
    final items = await _itemsByReferences(pageRefs);
    final nextOffset = start + pageRefs.length;
    _offsets[scope] = nextOffset;
    return _toFeedPage(
      items,
      hasMore: nextOffset < deduped.length,
      nextOffset: nextOffset,
    );
  }

  Future<List<CategoryEntity>> loadCategories() async {
    final categories = <CategoryEntity>[];
    final seen = <String>{};

    for (final entry in _contentTypeLabels.entries) {
      if (_hiddenContentTypes.contains(entry.key)) {
        continue;
      }
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

    final rows = List<Map<String, dynamic>>.of(await _loadCategoryRows());
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
      if (name.isEmpty ||
          slug.isEmpty ||
          !_catalogPagePrefixesByContentType.containsKey(contentType) ||
          _hiddenContentTypes.contains(contentType) ||
          _isBlockedCatalogLabel(name) ||
          _isBlockedCatalogLabel(slug) ||
          _isBlockedCatalogLabel(_string(row['parent_slug']))) {
        continue;
      }
      final key = '$contentType:$slug';
      if (!seen.add(key)) {
        continue;
      }
      const preview = '';
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

  Future<String> categoryPreviewUrl({required String contentType, required String slug}) async {
    final resolvedContentType = contentType.trim();
    final resolvedSlug = slug.trim();
    if (resolvedContentType.isEmpty ||
        _hiddenContentTypes.contains(resolvedContentType) ||
        !_catalogPagePrefixesByContentType.containsKey(resolvedContentType)) {
      return '';
    }

    String previewFromItem(_PrismItem item) {
      final candidate = _firstString(<Object?>[item.thumbnailUrl, item.staticThumbnailUrl, item.firstFrameThumbnailUrl]);
      return _isCatalogPreviewAssetUrl(candidate) ? '' : candidate;
    }

    try {
      if (resolvedSlug.isEmpty || resolvedSlug == 'for-you') {
        final page = await _loadCatalogPage(resolvedContentType, 1);
        for (final item in page.items) {
          final preview = previewFromItem(item).trim();
          if (preview.isNotEmpty) return preview;
        }
        return '';
      }

      final ids = await _categoryIdsFor(resolvedContentType, resolvedSlug);
      final items = await _itemsByIds(contentType: resolvedContentType, ids: ids.take(6).toList(growable: false));
      for (final item in items) {
        final preview = previewFromItem(item).trim();
        if (preview.isNotEmpty) return preview;
      }
    } catch (_) {
      // Category previews are visual polish; category navigation still works without them.
    }
    return '';
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
      if (trimmed.isEmpty || _isBlockedCatalogLabel(trimmed) || !seen.add(trimmed.toLowerCase())) {
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

  Future<CategoryFeedPage> search({required String query, required bool refresh, bool scanFullIndex = true}) async {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty || _isBlockedCatalogSearch(normalizedQuery)) {
      return const CategoryFeedPage(items: <FeedItemEntity>[], hasMore: false, nextCursor: null);
    }

    final scope = 'search.$normalizedQuery';
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final deduped = await _rankedSearchReferences(normalizedQuery, scanFullIndex: scanFullIndex);
    final refs = deduped.skip(start).take(_pageSize).toList(growable: false);
    final items = await _itemsByReferences(refs);
    final nextOffset = start + refs.length;
    _offsets[scope] = nextOffset;

    return _toFeedPage(
      items,
      hasMore: nextOffset < deduped.length,
      nextOffset: nextOffset,
    );
  }

  Future<CategoryFeedPage> searchAll({required String query}) {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty || _isBlockedCatalogSearch(normalizedQuery)) {
      return Future<CategoryFeedPage>.value(
        const CategoryFeedPage(items: <FeedItemEntity>[], hasMore: false, nextCursor: null),
      );
    }
    final cached = _searchAllFutures[normalizedQuery];
    if (cached != null) return cached;

    final future = _searchAllInternal(normalizedQuery);
    _searchAllFutures[normalizedQuery] = future;
    unawaited(
      future.catchError((Object _) {
        _searchAllFutures.remove(normalizedQuery);
        return const CategoryFeedPage(items: <FeedItemEntity>[], hasMore: false, nextCursor: null);
      }),
    );
    return future;
  }

  Future<CategoryFeedPage> _searchAllInternal(String normalizedQuery) async {
    final refs = await _rankedSearchReferences(normalizedQuery, scanFullIndex: true);
    final items = await _itemsByReferences(refs);
    return _toFeedPage(items, hasMore: false, nextOffset: items.length);
  }

  Future<List<_RankedItemReference>> _rankedSearchReferences(
    String normalizedQuery, {
    required bool scanFullIndex,
  }) async {
    final rankedRefs = await _rankedCategoryReferences(normalizedQuery);
    if (!scanFullIndex) {
      return _dedupeReferences(rankedRefs)..sort(_compareRankedReferences);
    }

    var ordinal = rankedRefs.length;
    final searchIndex = await _loadSearchIndex();
    for (final entry in searchIndex) {
      if (!_catalogPagePrefixesByContentType.containsKey(entry.contentType) ||
          _hiddenContentTypes.contains(entry.contentType)) {
        continue;
      }
      final score = _scoreSearchEntry(entry, normalizedQuery);
      if (score <= 0) {
        continue;
      }
      rankedRefs.add(
        _RankedItemReference(
          contentType: entry.contentType,
          id: entry.id,
          page: entry.page,
          score: score,
          ordinal: ordinal++,
          createdAt: entry.createdAt,
        ),
      );
    }
    return _dedupeReferences(rankedRefs)..sort(_compareRankedReferences);
  }

  Future<PrismWallpaper?> fetchById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    final locationsByContentType = await _loadItemLocations();
    for (final contentType in _catalogPagePrefixesByContentType.keys) {
      if (_hiddenContentTypes.contains(contentType)) {
        continue;
      }
      final page = locationsByContentType[contentType]?[trimmed];
      if (page == null) {
        continue;
      }
      final item = (await _loadCatalogPage(contentType, page)).byId(trimmed);
      if (item != null) return item.toWallpaper();
    }
    return null;
  }

  Future<CategoryFeedPage?> _fetchDirectApiPageFeed({
    required String contentType,
    required String slug,
    required String scope,
    required bool refresh,
  }) async {
    if (!_directApiEndpointsByContentType.containsKey(contentType) || _hiddenContentTypes.contains(contentType)) {
      return null;
    }

    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    var absoluteOffset = start;
    var remaining = _pageSize;
    var itemCount = 0;
    var lastHasMore = true;
    final items = <_PrismItem>[];

    while (remaining > 0 && lastHasMore) {
      final pageNumber = (absoluteOffset ~/ _catalogShardSize) + 1;
      final localOffset = absoluteOffset % _catalogShardSize;
      final directPage = await _loadDirectApiPage(
        contentType: contentType,
        slug: slug,
        page: pageNumber,
        refresh: refresh,
      );
      if (directPage == null) {
        return items.isEmpty ? null : _toFeedPage(items, hasMore: false, nextOffset: absoluteOffset);
      }

      itemCount = directPage.itemCount;
      lastHasMore = directPage.hasMore;
      final pageItems = directPage.items.skip(localOffset).take(remaining).toList(growable: false);
      if (pageItems.isEmpty) {
        break;
      }
      items.addAll(pageItems);
      absoluteOffset += pageItems.length;
      remaining -= pageItems.length;
    }

    if (items.isEmpty) {
      return null;
    }

    _offsets[scope] = absoluteOffset;
    return _toFeedPage(
      _dedupeItems(items),
      hasMore: absoluteOffset < itemCount && (lastHasMore || items.isNotEmpty),
      nextOffset: absoluteOffset,
    );
  }

  Future<_PrismCatalogPage?> _loadDirectApiPage({
    required String contentType,
    required String slug,
    required int page,
    required bool refresh,
  }) {
    final cacheKey = '$contentType.$slug.$page';
    if (refresh) {
      _directApiPageFutures.remove(cacheKey);
    }
    return _directApiPageFutures[cacheKey] ??= _loadDirectApiPageInternal(contentType: contentType, slug: slug, page: page);
  }

  Future<_PrismCatalogPage?> _loadDirectApiPageInternal({
    required String contentType,
    required String slug,
    required int page,
  }) async {
    final endpoint = _directApiEndpointsByContentType[contentType];
    if (endpoint == null || page <= 0) {
      return null;
    }

    for (final source in _directCatalogApiSources()) {
      try {
        final uri = _directApiUri(
          baseUrl: source.baseUrl,
          endpoint: endpoint,
          page: page,
          slug: slug,
          pageSize: _catalogShardSize,
        );
        final response = await http.get(uri, headers: source.headers).timeout(_pageTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300 || !_looksLikeJson(response.body)) {
          continue;
        }
        final payload = jsonDecode(response.body);
        final rawItems = _directPayloadItems(payload);
        if (rawItems.isEmpty) {
          continue;
        }
        final section = _directApiSectionsByContentType[contentType] ?? contentType;
        final items = _dedupeItems(
          rawItems.asMap().entries.map((entry) {
            final normalized = _normalizeDirectApiItem(
              entry.value,
              contentType: contentType,
              sourceBase: source.baseUrl,
              section: section,
              endpoint: endpoint,
              page: page,
              index: entry.key,
            );
            return _PrismItem.fromJson(normalized, contentType);
          }),
        );
        if (items.isEmpty) {
          continue;
        }
        final lastPage = _directPayloadLastPage(payload);
        final itemCount = _directPayloadItemCount(payload, page: page, pageSize: _catalogShardSize, itemCount: items.length);
        return _PrismCatalogPage(
          items: items,
          itemCount: itemCount,
          hasMore: lastPage == null ? items.length >= _catalogShardSize : page < lastPage,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<CategoryFeedPage> _fetchSequentialPageFeed({
    required String contentType,
    required String scope,
    required bool refresh,
  }) async {
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    var absoluteOffset = start;
    var remaining = _pageSize;
    var itemCount = 0;
    var lastHasMore = true;
    final items = <_PrismItem>[];

    while (remaining > 0 && lastHasMore) {
      final pageNumber = (absoluteOffset ~/ _catalogShardSize) + 1;
      final localOffset = absoluteOffset % _catalogShardSize;
      final catalogPage = await _loadCatalogPage(contentType, pageNumber);
      itemCount = catalogPage.itemCount;
      lastHasMore = catalogPage.hasMore;

      final pageItems = catalogPage.items.skip(localOffset).take(remaining).toList(growable: false);
      if (pageItems.isEmpty) {
        break;
      }
      items.addAll(pageItems);
      absoluteOffset += pageItems.length;
      remaining -= pageItems.length;
    }

    _offsets[scope] = absoluteOffset;
    return _toFeedPage(
      items,
      hasMore: absoluteOffset < itemCount && (lastHasMore || items.isNotEmpty),
      nextOffset: absoluteOffset,
    );
  }

  CategoryFeedPage _toFeedPage(List<_PrismItem> items, {required bool hasMore, required int nextOffset}) {
    return CategoryFeedPage(
      items: items.map((item) => PrismFeedItem(id: item.id, wallpaper: item.toWallpaper())).toList(growable: false),
      hasMore: hasMore,
      nextCursor: nextOffset.toString(),
    );
  }

  Future<List<Map<String, dynamic>>> _loadCategoryRows() {
    return _categoryRowsFuture ??= _loadCategoryRowsInternal();
  }

  Future<List<Map<String, dynamic>>> _loadCategoryRowsInternal() async {
    try {
      return await _loadCategoryRowsFromFile('prism_category_lite.json');
    } catch (_) {
      return _loadCategoryRowsFromFile('prism_category_trees.json');
    }
  }

  Future<List<Map<String, dynamic>>> _loadCategoryRowsFromFile(String fileName) async {
    final raw = await _loadCatalogJson(fileName, timeout: _metadataTimeout);
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final rawCategories = payload['categories'];
    return rawCategories is List
        ? rawCategories.whereType<Map>().map(_asMap).toList(growable: false)
        : <Map<String, dynamic>>[];
  }

  Future<List<String>> _categoryIdsFor(String contentType, String slug) async {
    final categoryIds = await _loadCategoryIds();
    return categoryIds[contentType]?[slug] ?? const <String>[];
  }

  Future<Map<String, Map<String, List<String>>>> _loadCategoryIds() {
    return _categoryIdsFuture ??= _loadCategoryIdsInternal();
  }

  Future<Map<String, Map<String, List<String>>>> _loadCategoryIdsInternal() async {
    try {
      final raw = await _loadCatalogJson(
        'prism_category_ids.json',
        timeout: _metadataTimeout,
        allowGeneratedFallback: false,
      );
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final contentTypes = _asMap(payload['content_types']);
      return <String, Map<String, List<String>>>{
        for (final contentTypeEntry in contentTypes.entries)
          contentTypeEntry.key: <String, List<String>>{
            for (final categoryEntry in _asMap(contentTypeEntry.value).entries)
              categoryEntry.key: _strings(categoryEntry.value),
          },
      };
    } catch (_) {
      return _buildCategoryIdsFromCompactCatalogs();
    }
  }

  Future<Map<String, Map<String, int>>> _loadItemLocations() {
    return _itemLocationsFuture ??= _loadItemLocationsInternal();
  }

  Future<Map<String, Map<String, int>>> _loadItemLocationsInternal() async {
    try {
      final raw = await _loadCatalogJson(
        'prism_item_locations.json',
        timeout: _metadataTimeout,
        allowGeneratedFallback: false,
      );
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final contentTypes = _asMap(payload['content_types']);
      return <String, Map<String, int>>{
        for (final contentTypeEntry in contentTypes.entries)
          contentTypeEntry.key: <String, int>{
            for (final itemEntry in _asMap(contentTypeEntry.value).entries)
              if (_int(itemEntry.value) != null) itemEntry.key: _int(itemEntry.value)!,
          },
      };
    } catch (_) {
      return _buildItemLocationsFromCompactCatalogs();
    }
  }

  Future<List<_SearchIndexEntry>> _loadSearchIndex() {
    return _searchIndexFuture ??= _loadSearchIndexInternal();
  }

  Future<List<_SearchIndexEntry>> _loadSearchIndexInternal() async {
    try {
      final raw = await _loadCatalogJson(
        'prism_search_index.json',
        timeout: _searchIndexTimeout,
        allowGeneratedFallback: false,
      );
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final rawItems = payload['items'];
      if (rawItems is! List) {
        return const <_SearchIndexEntry>[];
      }
      return rawItems.whereType<Map>().map((item) => _SearchIndexEntry.fromJson(_asMap(item))).toList(growable: false);
    } catch (_) {
      return _buildSearchIndexFromCompactCatalogs();
    }
  }

  Future<_PrismCatalogPage> _loadCatalogPage(String contentType, int page) {
    final prefix = _catalogPagePrefixesByContentType[contentType];
    if (prefix == null || page <= 0) {
      return Future<_PrismCatalogPage>.error(
        ArgumentError.value(contentType, 'contentType', 'Unsupported catalog type'),
      );
    }
    final cacheKey = '$contentType.$page';
    return _pageFutures[cacheKey] ??= _loadCatalogPageFile(prefix: prefix, fallbackType: contentType, page: page);
  }

  Future<_PrismCatalogPage> _loadCatalogPageFile({
    required String prefix,
    required String fallbackType,
    required int page,
  }) async {
    final fileName = '${prefix}_page_${page.toString().padLeft(3, '0')}.json';
    try {
      final raw = await _loadCatalogJson(fileName, timeout: _pageTimeout, allowGeneratedFallback: false);
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final contentType = _string(payload['content_type']).isNotEmpty ? _string(payload['content_type']) : fallbackType;
      final rawItems = payload['wallpapers'];
      final items = rawItems is List
          ? _dedupeItems(rawItems.whereType<Map>().map((item) => _PrismItem.fromJson(_asMap(item), contentType)))
          : <_PrismItem>[];
      return _PrismCatalogPage(
        items: items,
        itemCount: _int(payload['item_count']) ?? items.length,
        hasMore: payload['has_more'] == true,
      );
    } catch (_) {
      return _loadCompactCatalogPage(contentType: fallbackType, page: page);
    }
  }

  Future<_PrismCatalogPage> _loadCompactCatalogPage({required String contentType, required int page}) async {
    final items = await _loadCompactCatalog(contentType);
    final start = (page - 1) * _catalogShardSize;
    if (start >= items.length) {
      return _PrismCatalogPage(items: const <_PrismItem>[], itemCount: items.length, hasMore: false);
    }
    final pageItems = items.skip(start).take(_catalogShardSize).toList(growable: false);
    return _PrismCatalogPage(
      items: pageItems,
      itemCount: items.length,
      hasMore: start + pageItems.length < items.length,
    );
  }

  Future<List<_PrismItem>> _loadCompactCatalog(String contentType) {
    final fileName = _catalogFilesByContentType[contentType];
    if (fileName == null) {
      return Future<List<_PrismItem>>.value(const <_PrismItem>[]);
    }
    return _compactCatalogFutures[contentType] ??= _loadCompactCatalogFile(
      contentType: contentType,
      fileName: fileName,
    );
  }

  Future<List<_PrismItem>> _loadCompactCatalogFile({required String contentType, required String fileName}) async {
    try {
      final raw = await _loadCatalogJson(fileName, timeout: _metadataTimeout);
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final resolvedType = _string(payload['content_type']).isNotEmpty ? _string(payload['content_type']) : contentType;
      final rawItems = payload['wallpapers'];
      if (rawItems is! List) {
        return const <_PrismItem>[];
      }
      return _dedupeItems(rawItems.whereType<Map>().map((item) => _PrismItem.fromJson(_asMap(item), resolvedType)));
    } catch (_) {
      return const <_PrismItem>[];
    }
  }

  Future<Map<String, Map<String, List<String>>>> _buildCategoryIdsFromCompactCatalogs() async {
    final result = <String, Map<String, List<String>>>{};
    await Future.wait<void>([
      for (final contentType in _catalogPagePrefixesByContentType.keys)
        () async {
          if (_hiddenContentTypes.contains(contentType)) {
            return;
          }
          final items = await _loadCompactCatalog(contentType);
          final bySlug = result.putIfAbsent(contentType, () => <String, List<String>>{});
          for (final item in items) {
            if (item.id.trim().isEmpty) {
              continue;
            }
            for (final slug in item.categorySlugs) {
              final normalizedSlug = slug.trim();
              if (normalizedSlug.isEmpty) {
                continue;
              }
              bySlug.putIfAbsent(normalizedSlug, () => <String>[]).add(item.id);
            }
          }
        }(),
    ]);
    return result;
  }

  Future<Map<String, Map<String, int>>> _buildItemLocationsFromCompactCatalogs() async {
    final result = <String, Map<String, int>>{};
    await Future.wait<void>([
      for (final contentType in _catalogPagePrefixesByContentType.keys)
        () async {
          if (_hiddenContentTypes.contains(contentType)) {
            return;
          }
          final items = await _loadCompactCatalog(contentType);
          final locations = result.putIfAbsent(contentType, () => <String, int>{});
          for (var index = 0; index < items.length; index++) {
            final id = items[index].id.trim();
            if (id.isEmpty) {
              continue;
            }
            locations[id] = (index ~/ _catalogShardSize) + 1;
          }
        }(),
    ]);
    return result;
  }

  Future<List<_SearchIndexEntry>> _buildSearchIndexFromCompactCatalogs() async {
    final entries = <_SearchIndexEntry>[];
    await Future.wait<void>([
      for (final contentType in _catalogPagePrefixesByContentType.keys)
        () async {
          if (_hiddenContentTypes.contains(contentType)) {
            return;
          }
          final items = await _loadCompactCatalog(contentType);
          for (var index = 0; index < items.length; index++) {
            final item = items[index];
            if (item.id.trim().isEmpty) {
              continue;
            }
            entries.add(
              _SearchIndexEntry(
                id: item.id,
                contentType: contentType,
                page: (index ~/ _catalogShardSize) + 1,
                name: item.name,
                slug: item.slug,
                categoryNames: item.categoryNames,
                categorySlugs: item.categorySlugs,
                tags: item.tags,
                createdAt: item.createdAt,
              ),
            );
          }
        }(),
    ]);
    return entries;
  }

  Future<List<_PrismItem>> _itemsByIds({required String contentType, required List<String> ids}) async {
    if (ids.isEmpty) {
      return const <_PrismItem>[];
    }
    final locations = await _loadItemLocations();
    final pages = locations[contentType] ?? const <String, int>{};
    final refs = <_RankedItemReference>[
      for (var index = 0; index < ids.length; index++)
        if (pages[ids[index]] != null)
          _RankedItemReference(
            contentType: contentType,
            id: ids[index],
            page: pages[ids[index]],
            score: 0,
            ordinal: index,
            createdAt: null,
          ),
    ];
    return _itemsByReferences(refs);
  }

  Future<List<_PrismItem>> _itemsByReferences(List<_RankedItemReference> refs) async {
    if (refs.isEmpty) {
      return const <_PrismItem>[];
    }

    final locationsByContentType = await _loadItemLocations();
    final byPage = <String, Map<int, List<_RankedItemReference>>>{};
    for (final ref in refs) {
      if (!_catalogPagePrefixesByContentType.containsKey(ref.contentType)) {
        continue;
      }
      final page = ref.page ?? locationsByContentType[ref.contentType]?[ref.id];
      if (page == null) {
        continue;
      }
      byPage
          .putIfAbsent(ref.contentType, () => <int, List<_RankedItemReference>>{})
          .putIfAbsent(page, () => <_RankedItemReference>[])
          .add(ref);
    }

    final itemsByKey = <String, _PrismItem>{};
    await Future.wait<void>([
      for (final contentTypeEntry in byPage.entries)
        for (final pageEntry in contentTypeEntry.value.entries)
          () async {
            final catalogPage = await _loadCatalogPage(contentTypeEntry.key, pageEntry.key);
            for (final ref in pageEntry.value) {
              final item = catalogPage.byId(ref.id);
              if (item != null) {
                itemsByKey['${ref.contentType}:${ref.id}'] = item;
              }
            }
          }(),
    ]);

    return refs
        .map((ref) => itemsByKey['${ref.contentType}:${ref.id}'])
        .whereType<_PrismItem>()
        .toList(growable: false);
  }

  Future<List<_RankedItemReference>> _rankedCategoryReferences(String normalizedQuery) async {
    final rows = await _loadCategoryRows();
    final categoryIds = await _loadCategoryIds();
    final hits = <_RankedCategory>[];

    for (final row in rows) {
      final name = _string(row['name']).trim();
      final slug = _string(row['slug']).trim();
      final contentType = _contentTypeForCategory(row);
      if (name.isEmpty ||
          slug.isEmpty ||
          !_catalogPagePrefixesByContentType.containsKey(contentType) ||
          _hiddenContentTypes.contains(contentType) ||
          _isBlockedCatalogLabel(name) ||
          _isBlockedCatalogLabel(slug) ||
          _isBlockedCatalogLabel(_string(row['parent_slug']))) {
        continue;
      }
      final score = _scoreSearchFieldsWithAliases(
        normalizedQuery: normalizedQuery,
        name: name,
        slug: slug,
        categories: const <String>[],
        categorySlugs: const <String>[],
        tags: const <String>[],
      );
      if (score > 0) {
        hits.add(
          _RankedCategory(
            contentType: contentType,
            slug: slug,
            score: score + 1000,
            position: _int(row['position']) ?? 999999,
          ),
        );
      }
    }

    hits.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.position.compareTo(b.position);
    });

    var ordinal = 0;
    final refs = <_RankedItemReference>[];
    final locations = await _loadItemLocations();
    for (final hit in hits) {
      final ids = categoryIds[hit.contentType]?[hit.slug] ?? const <String>[];
      final pages = locations[hit.contentType] ?? const <String, int>{};
      for (final id in ids) {
        refs.add(
          _RankedItemReference(
            contentType: hit.contentType,
            id: id,
            page: pages[id],
            score: hit.score,
            ordinal: ordinal++,
            createdAt: null,
          ),
        );
      }
    }
    return _dedupeReferences(refs)..sort(_compareRankedReferences);
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

  Future<String> _loadCatalogJson(
    String fileName, {
    Duration timeout = _metadataTimeout,
    bool allowGeneratedFallback = true,
    bool preferCache = false,
  }) async {
    final cacheKey = PersistenceKeys.cachePrismCatalog(fileName);
    final cached = await _readCachedCatalogJson(cacheKey);
    if (cached != null && _looksLikeJson(cached) && (preferCache || _shouldServeCachedCatalogFirst(fileName))) {
      unawaited(_refreshCatalogJsonCache(fileName: fileName, cacheKey: cacheKey, timeout: timeout));
      return cached;
    }

    if (preferCache && fileName == _homeBootstrapFile) {
      try {
        final bundled = await rootBundle.loadString('assets/catalog/$fileName');
        unawaited(_writeCachedCatalogJson(cacheKey, bundled));
        unawaited(_refreshCatalogJsonCache(fileName: fileName, cacheKey: cacheKey, timeout: timeout));
        return bundled;
      } catch (_) {
        // A missing bundled bootstrap can still fall through to remote/catalog fallback.
      }
    }

    final remote = await _fetchRemoteCatalogJson(fileName: fileName, timeout: timeout);
    if (remote != null) {
      unawaited(_writeCachedCatalogJson(cacheKey, remote));
      return remote;
    }

    try {
      final bundled = await rootBundle.loadString('assets/catalog/$fileName');
      unawaited(_writeCachedCatalogJson(cacheKey, bundled));
      return bundled;
    } catch (bundleError) {
      if (cached != null && _looksLikeJson(cached)) {
        return cached;
      }
      if (!allowGeneratedFallback) {
        throw StateError('Missing required catalog asset $fileName: $bundleError');
      }
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
      throw StateError('Missing catalog asset $fileName: $bundleError');
    }
  }

  Future<String?> _readCachedCatalogJson(String cacheKey) async {
    try {
      final raw = await _catalogCache.get(cacheKey);
      return raw is String ? raw : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedCatalogJson(String cacheKey, String body) async {
    if (!_looksLikeJson(body)) {
      return;
    }
    try {
      await _catalogCache.set(cacheKey, body);
    } catch (_) {
      // Disk cache is an optimization; the remote/bundled response remains valid.
    }
  }

  bool _looksLikeJson(String body) {
    final trimmed = body.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  bool _shouldServeCachedCatalogFirst(String fileName) {
    return fileName != _homeBootstrapFile && fileName.startsWith('prism_') && fileName.endsWith('.json');
  }

  Future<String?> _fetchRemoteCatalogJson({required String fileName, required Duration timeout}) async {
    final remoteBase = _remoteCatalogBaseUrl;
    if (remoteBase.isEmpty) {
      return null;
    }
    final base = remoteBase.endsWith('/') ? remoteBase.substring(0, remoteBase.length - 1) : remoteBase;
    try {
      final response = await http.get(Uri.parse('$base/$fileName')).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300 && _looksLikeJson(response.body)) {
        return response.body;
      }
    } catch (_) {
      // Remote catalog refresh failure falls back to bundled or cached data.
    }
    return null;
  }

  Future<void> _refreshCatalogJsonCache({required String fileName, required String cacheKey, required Duration timeout}) async {
    final remote = await _fetchRemoteCatalogJson(fileName: fileName, timeout: timeout);
    if (remote == null) {
      return;
    }
    await _writeCachedCatalogJson(cacheKey, remote);
  }

  Future<void> _warmCatalogJsonFiles() async {
    const files = <String>[
      'prism_index.json',
      'prism_category_lite.json',
      'prism_category_trees.json',
      'prism_category_ids.json',
      'prism_item_locations.json',
      'prism_popular_searches.json',
      'prism_search_suggestions.json',
      'prism_regular_page_001.json',
      'prism_regular_page_002.json',
      'prism_regular_page_003.json',
      'prism_live_page_001.json',
      'prism_live_page_002.json',
      'prism_live_page_003.json',
      'prism_matching_page_001.json',
      'prism_matching_page_002.json',
      'prism_matching_page_003.json',
      'prism_double_page_001.json',
      'prism_double_page_002.json',
      'prism_double_page_003.json',
      'prism_parallax_page_001.json',
      'prism_parallax_page_002.json',
      'prism_parallax_page_003.json',
      'prism_profile_pictures_page_001.json',
      'prism_profile_pictures_page_002.json',
      'prism_profile_pictures_page_003.json',
      'prism_search_index.json',
    ];
    const batchSize = 4;
    for (var index = 0; index < files.length; index += batchSize) {
      final batch = files.skip(index).take(batchSize);
      await Future.wait<void>(
        batch.map((fileName) async {
          final timeout = fileName == 'prism_search_index.json' ? _searchIndexTimeout : _metadataTimeout;
          try {
            await _refreshCatalogJsonCache(
              fileName: fileName,
              cacheKey: PersistenceKeys.cachePrismCatalog(fileName),
              timeout: timeout,
            );
          } catch (_) {
            // Cache warmup is opportunistic and must never block app launch.
          }
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
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
    if (_catalogPagePrefixesByContentType.containsKey(type)) {
      return type;
    }
    return _numericCategoryTypes[type] ?? regularContentType;
  }
}

class PrismCatalogHomeBootstrap {
  const PrismCatalogHomeBootstrap({
    required this.generatedAt,
    required this.sections,
    required this.prefetchUrls,
  });

  final DateTime? generatedAt;
  final List<PrismCatalogHomeBootstrapSection> sections;
  final List<String> prefetchUrls;

  factory PrismCatalogHomeBootstrap.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    return PrismCatalogHomeBootstrap(
      generatedAt: DateTime.tryParse(_string(json['generated_at']))?.toUtc(),
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((section) => PrismCatalogHomeBootstrapSection.fromJson(_asMap(section)))
              .where((section) => section.items.isNotEmpty)
              .toList(growable: false)
          : const <PrismCatalogHomeBootstrapSection>[],
      prefetchUrls: _strings(json['prefetch_urls']),
    );
  }
}

class PrismCatalogHomeBootstrapSection {
  const PrismCatalogHomeBootstrapSection({
    required this.title,
    required this.contentType,
    required this.slug,
    required this.kind,
    required this.items,
  });

  final String title;
  final String contentType;
  final String slug;
  final String kind;
  final List<FeedItemEntity> items;

  factory PrismCatalogHomeBootstrapSection.fromJson(Map<String, dynamic> json) {
    final contentType = _string(json['content_type']).isNotEmpty
        ? _string(json['content_type'])
        : PrismCatalogDataSource.regularContentType;
    final rawItems = json['wallpapers'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((row) {
            final item = _PrismItem.fromJson(_asMap(row), contentType);
            return PrismFeedItem(id: item.id, wallpaper: item.toWallpaper());
          }).where((item) => item.id.trim().isNotEmpty).toList(growable: false)
        : const <FeedItemEntity>[];

    return PrismCatalogHomeBootstrapSection(
      title: _string(json['title']).isNotEmpty ? _string(json['title']) : 'For You',
      contentType: contentType,
      slug: _string(json['slug']).isNotEmpty ? _string(json['slug']) : 'for-you',
      kind: _string(json['kind']),
      items: items,
    );
  }
}

class _PrismCatalogPage {
  _PrismCatalogPage({
    required this.items,
    required this.itemCount,
    required this.hasMore,
  }) : _byId = <String, _PrismItem>{for (final item in items) item.id: item};

  final List<_PrismItem> items;
  final int itemCount;
  final bool hasMore;
  final Map<String, _PrismItem> _byId;

  _PrismItem? byId(String id) => _byId[id];
}

class _RankedCategory {
  const _RankedCategory({
    required this.contentType,
    required this.slug,
    required this.score,
    required this.position,
  });

  final String contentType;
  final String slug;
  final int score;
  final int position;
}

class _RankedItemReference {
  const _RankedItemReference({
    required this.contentType,
    required this.id,
    required this.page,
    required this.score,
    required this.ordinal,
    required this.createdAt,
  });

  final String contentType;
  final String id;
  final int? page;
  final int score;
  final int ordinal;
  final DateTime? createdAt;
}

class _SearchIndexEntry {
  const _SearchIndexEntry({
    required this.id,
    required this.contentType,
    required this.page,
    required this.name,
    required this.slug,
    required this.categoryNames,
    required this.categorySlugs,
    required this.tags,
    required this.createdAt,
  });

  final String id;
  final String contentType;
  final int? page;
  final String name;
  final String slug;
  final List<String> categoryNames;
  final List<String> categorySlugs;
  final List<String> tags;
  final DateTime? createdAt;

  factory _SearchIndexEntry.fromJson(Map<String, dynamic> json) {
    return _SearchIndexEntry(
      id: _string(json['id']),
      contentType: _string(json['content_type']),
      page: _int(json['page']),
      name: _string(json['name']),
      slug: _string(json['slug']),
      categoryNames: _strings(json['categories']),
      categorySlugs: _strings(json['category_slugs']),
      tags: _strings(json['tags']),
      createdAt: DateTime.tryParse(_string(json['created_at']))?.toUtc(),
    );
  }
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
    required this.firstFrameThumbnailUrl,
    required this.videoUrl,
    required this.thumbnailVideoUrl,
    required this.templateUrl,
    required this.parallaxFileUrl,
    required this.mediaAssetUrls,
    required this.pairedWallpapers,
    required this.matchingSides,
    required this.pairedPreviewUrls,
    required this.pairedDownloadUrls,
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
  final String firstFrameThumbnailUrl;
  final String videoUrl;
  final String thumbnailVideoUrl;
  final String templateUrl;
  final String parallaxFileUrl;
  final List<String> mediaAssetUrls;
  final List<Map<String, dynamic>> pairedWallpapers;
  final List<Map<String, dynamic>> matchingSides;
  final List<String> pairedPreviewUrls;
  final List<String> pairedDownloadUrls;
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
    final sourceBase = _firstString(<Object?>[json['source'], json['media_source'], Env.normalize(Env.prismMediaBaseUrl)]);
    String url(Object? value) => _resolveCatalogUrl(value, sourceBase: sourceBase);

    final wallpaper = url(json['wallpaper']);
    final image = url(json['image']);
    final template = url(json['template']);
    final sticker = url(json['sticker']);
    final parallaxFile = url(json['parallax_file']);
    final catalogDownload = url(json['download_url']);
    final appDisplayUrl = url(json['app_display_url']);
    final appDownloadUrl = url(json['app_download_url']);
    final pairedWallpapers = _maps(json['paired_wallpapers']);
    final appMatchingSides = _maps(json['app_matching_sides']);
    final explicitPairedDownloadUrls = <String>[
      ..._strings(json['paired_download_urls']).map((value) => url(value)),
      ...appMatchingSides.map((side) => url(side['download_url'])),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    final derivedPairedDownloadUrls = pairedWallpapers
        .map((wallpaper) => _firstString(<Object?>[
              url(wallpaper['download_url']),
              url(wallpaper['wallpaper']),
              url(wallpaper['image']),
              url(wallpaper['full_url']),
              url(wallpaper['url']),
            ]))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final pairedDownloadUrls = _uniqueStrings(<String>[
      ...explicitPairedDownloadUrls,
      ...derivedPairedDownloadUrls,
    ].where(_isActualCatalogImageUrl));
    final derivedPairedPreviewUrls = pairedWallpapers
        .map((wallpaper) => _firstString(<Object?>[
              url(wallpaper['wallpaper']),
              url(wallpaper['image']),
              url(wallpaper['download_url']),
              url(wallpaper['full_url']),
              url(wallpaper['url']),
            ]))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final pairedDownloadDisplayUrls = _uniqueStrings(pairedDownloadUrls.map(_fastTileOrOriginal));
    final pairedFallbackPreviewUrls = _uniqueStrings(<String>[
      ...derivedPairedPreviewUrls.where(_isActualCatalogImageUrl).map(_fastTileOrOriginal),
    ]);
    final pairedDisplayUrls = pairedDownloadDisplayUrls.isNotEmpty ? pairedDownloadDisplayUrls : pairedFallbackPreviewUrls;
    final normalizedMatchingSides = <Map<String, dynamic>>[
      for (var index = 0; index < appMatchingSides.length; index++)
        <String, dynamic>{
          ...appMatchingSides[index],
          'download_url': _isActualCatalogImageUrl(url(appMatchingSides[index]['download_url']))
              ? url(appMatchingSides[index]['download_url'])
              : '',
          'preview_url': index < pairedDisplayUrls.length
              ? pairedDisplayUrls[index]
              : _isActualCatalogImageUrl(url(appMatchingSides[index]['download_url']))
                  ? _fastTileOrOriginal(url(appMatchingSides[index]['download_url']))
                  : '',
        },
    ];
    final mediaAssetUrls = _strings(json['media_assets'])
        .map((value) => url(value))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final video = _firstString(<Object?>[
      url(json['video_original ']),
      url(json['video_original']),
      url(json['video']),
      url(json['lq_video']),
    ]);
    final firstFrameThumbnail = url(json['first_frame_thumbnail']);
    final thumbnail = url(json['thumbnail']);
    final staticThumbnail = url(json['static_thumbnail']);
    final hqThumbnail = url(json['hq_thumbnail']);
    bool isVideoUrl(String value) {
      final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
      return path.endsWith('.mp4') || path.endsWith('.mov');
    }

    bool isArchiveUrl(String value) {
      final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
      return path.endsWith('.zip');
    }

    bool isImageUrl(String value) {
      if (value.trim().isEmpty || isVideoUrl(value) || isArchiveUrl(value)) {
        return false;
      }
      final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
      return path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.png') ||
          path.endsWith('.webp') ||
          path.endsWith('.gif');
    }

    bool isActualImageUrl(String value) => isImageUrl(value) && _isActualCatalogImageUrl(value);

    final fastVideo = _fastVideoOrOriginal(video);
    final fastThumbnailVideo = _fastVideoOrOriginal(url(json['thumbnail_video']));
    final fastAppDownloadVideo = isVideoUrl(appDownloadUrl) ? _fastVideoOrOriginal(appDownloadUrl) : '';
    final fastCatalogDownloadVideo = isVideoUrl(catalogDownload) ? _fastVideoOrOriginal(catalogDownload) : '';
    final fastWallpaperVideo = isVideoUrl(wallpaper) ? _fastVideoOrOriginal(wallpaper) : '';

    String firstParallaxLayerImage() {
      final thumbnailConfig = _asMap(json['thumbnail_config']);
      for (final layer in _maps(thumbnailConfig['layers'])) {
        final candidate = url(layer['url']);
        if (isActualImageUrl(candidate)) {
          return candidate;
        }
      }
      return '';
    }

    final isLiveContent = contentType == PrismCatalogDataSource.liveContentType;
    final isParallaxContent = contentType == PrismCatalogDataSource.parallaxContentType;
    final isProfilePictureContent = contentType == PrismCatalogDataSource.profilePictureContentType;
    final isMatchingContent = contentType == PrismCatalogDataSource.matchingContentType ||
        contentType == PrismCatalogDataSource.doubleContentType;
    final parallaxArchive = isParallaxContent
        ? _firstString(<Object?>[
            isArchiveUrl(appDownloadUrl) ? appDownloadUrl : '',
            isArchiveUrl(appDisplayUrl) ? appDisplayUrl : '',
            isArchiveUrl(catalogDownload) ? catalogDownload : '',
            isArchiveUrl(parallaxFile) ? parallaxFile : '',
          ])
        : '';
    final imageDownload = _firstString(<Object?>[
      isActualImageUrl(appDownloadUrl) ? appDownloadUrl : '',
      isActualImageUrl(appDisplayUrl) ? appDisplayUrl : '',
      isActualImageUrl(catalogDownload) ? catalogDownload : '',
    ]);
    final fullImage = _firstString(<Object?>[
      imageDownload,
      isActualImageUrl(wallpaper) ? wallpaper : '',
      isActualImageUrl(image) ? image : '',
      isActualImageUrl(sticker) ? sticker : '',
    ]);
    final fullMedia = _firstString(<Object?>[
      appDownloadUrl,
      appDisplayUrl,
      catalogDownload,
      video,
      wallpaper,
      image,
      sticker,
      parallaxFile,
    ]);
    final livePoster = _firstString(<Object?>[
      isActualImageUrl(fullImage) ? fullImage : '',
      isActualImageUrl(appDisplayUrl) ? appDisplayUrl : '',
      isActualImageUrl(appDownloadUrl) ? appDownloadUrl : '',
      isActualImageUrl(catalogDownload) ? catalogDownload : '',
      isActualImageUrl(wallpaper) ? wallpaper : '',
      isActualImageUrl(image) ? image : '',
    ]);
    final parallaxLayerPreview = firstParallaxLayerImage();
    final fastFullImage = _fastTileOrOriginal(fullImage);
    final fastFullSizeImage = _fastTileOrOriginal(fullImage, width: 3840, quality: 98);
    final fastLivePoster = _fastTileOrOriginal(livePoster);
    final parallaxTileImage = _firstString(<Object?>[
      _fastTileOrOriginal(parallaxLayerPreview, width: 3840, quality: 98),
      fastFullSizeImage,
    ]);
    final parallaxDisplayImage = isParallaxContent
        ? _firstString(<Object?>[
            fastFullSizeImage,
            parallaxTileImage,
            fastFullImage,
            fullImage,
          ])
        : '';
    final tileImage = _firstString(<Object?>[
      isMatchingContent ? _firstString(<Object?>[...pairedDisplayUrls]) : '',
      fastFullImage,
      fastLivePoster,
    ]);
    final thumb = isLiveContent
        ? _firstString(<Object?>[fastLivePoster, tileImage])
        : isParallaxContent
            ? _firstString(<Object?>[parallaxTileImage, fastFullImage])
            : tileImage;
    final staticThumb = isLiveContent
        ? _firstString(<Object?>[fastLivePoster, thumb])
        : _firstString(<Object?>[
            isActualImageUrl(staticThumbnail) ? _fastTileOrOriginal(staticThumbnail) : '',
            isActualImageUrl(hqThumbnail) ? _fastTileOrOriginal(hqThumbnail) : '',
            thumb,
            fastFullImage,
          ]);
    final preview = isMatchingContent
        ? _firstString(<Object?>[...pairedDisplayUrls, fullImage, thumb])
        : isLiveContent
            ? _firstString(<Object?>[fastVideo, fastAppDownloadVideo, fastCatalogDownloadVideo, fastWallpaperVideo, fullImage, livePoster])
            : isParallaxContent
                ? _firstString(<Object?>[parallaxDisplayImage, thumb])
                : _firstString(<Object?>[fullImage, thumb]);
    final displayOnlyContent = contentType == PrismCatalogDataSource.diyTemplateContentType ||
        contentType == PrismCatalogDataSource.liveDiyTemplateContentType;
    final download = isParallaxContent
        ? _firstString(<Object?>[fastFullSizeImage, imageDownload, fullImage, parallaxDisplayImage, thumb])
        : displayOnlyContent
        ? _firstString(<Object?>[parallaxArchive, appDownloadUrl, fullImage, preview, thumb, template, fullMedia])
        : isMatchingContent
            ? _firstString(<Object?>[...pairedDownloadUrls, imageDownload, fullImage, ...pairedDisplayUrls])
            : isLiveContent
                ? _firstString(<Object?>[
                    fastVideo,
                    fastAppDownloadVideo,
                    fastCatalogDownloadVideo,
                    fastWallpaperVideo,
                    isVideoUrl(appDownloadUrl) ? appDownloadUrl : '',
                    isVideoUrl(catalogDownload) ? catalogDownload : '',
                    video,
                    isVideoUrl(wallpaper) ? wallpaper : '',
                  ])
                : _firstString(<Object?>[imageDownload, fullImage]);
    final rawWidth = _int(json['width']);
    final rawHeight = _int(json['height']);
    final normalizedSize = _normalizedCatalogSize(
      contentType: contentType,
      width: rawWidth,
      height: rawHeight,
    );
    return _PrismItem(
      id: _string(json['id']),
      name: _string(json['name']),
      slug: _string(json['slug']),
      description: _string(json['description']),
      contentType: contentType,
      width: normalizedSize.width,
      height: normalizedSize.height,
      downloadUrl: download,
      previewUrl: preview,
      thumbnailUrl: thumb,
      staticThumbnailUrl: staticThumb,
      firstFrameThumbnailUrl: isLiveContent
          ? fastLivePoster
          : isActualImageUrl(firstFrameThumbnail)
              ? _fastTileOrOriginal(firstFrameThumbnail)
              : '',
      videoUrl: fastVideo,
      thumbnailVideoUrl: fastThumbnailVideo,
      templateUrl: template.isNotEmpty ? template : catalogDownload,
      parallaxFileUrl: parallaxArchive,
      mediaAssetUrls: mediaAssetUrls,
      pairedWallpapers: pairedWallpapers,
      matchingSides: normalizedMatchingSides,
      pairedPreviewUrls: pairedDisplayUrls,
      pairedDownloadUrls: pairedDownloadUrls,
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
    final displayOnlyContent = contentType == PrismCatalogDataSource.diyTemplateContentType ||
        contentType == PrismCatalogDataSource.liveDiyTemplateContentType ||
        contentType == PrismCatalogDataSource.chargingAnimationContentType;
    final String thumb = contentType == PrismCatalogDataSource.liveContentType
        ? _firstString(<Object?>[thumbnailUrl, staticThumbnailUrl, firstFrameThumbnailUrl])
        : (contentType == PrismCatalogDataSource.matchingContentType ||
                contentType == PrismCatalogDataSource.doubleContentType)
            ? _firstString(<Object?>[...pairedPreviewUrls, ...pairedDownloadUrls, thumbnailUrl, previewUrl, full])
            : contentType == PrismCatalogDataSource.profilePictureContentType
                ? _firstString(<Object?>[thumbnailUrl, previewUrl, full, staticThumbnailUrl])
                : displayOnlyContent
                    ? _firstString(<Object?>[thumbnailUrl, staticThumbnailUrl, previewUrl, full])
                    : _firstString(<Object?>[thumbnailUrl, staticThumbnailUrl, previewUrl, full]);
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
        'catalogName': name,
        'catalogSlug': slug,
        'catalogDescription': description,
        'catalogPreviewUrl': previewUrl,
        'catalogStaticThumbnailUrl': staticThumbnailUrl,
        'catalogFirstFrameThumbnailUrl': firstFrameThumbnailUrl,
        'catalogVideoUrl': videoUrl,
        'catalogThumbnailVideoUrl': thumbnailVideoUrl,
        'catalogTemplateUrl': templateUrl,
        'catalogParallaxFileUrl': parallaxFileUrl,
        'catalogMediaAssetUrls': mediaAssetUrls,
        'catalogPairedWallpapers': pairedWallpapers,
        'catalogMatchingSides': matchingSides,
        'catalogPairedPreviewUrls': pairedPreviewUrls,
        'catalogPairedDownloadUrls': pairedDownloadUrls,
        'catalogIsPremium': isPremium,
      },
      remoteStoreDocumentId: 'prism-$id',
    );
  }
}


class _DirectCatalogApiSource {
  const _DirectCatalogApiSource({required this.baseUrl, required this.headers});

  final String baseUrl;
  final Map<String, String> headers;
}

List<_DirectCatalogApiSource> _directCatalogApiSources() {
  final sources = <_DirectCatalogApiSource>[];
  final wallPicsHeaders = _wallPicsApiHeaders();
  final configuredWallPicsBase = Env.normalize(Env.wallPicsApiBaseUrl).replaceAll(RegExp(r'/+$'), '');
  final hasWallPicsAuth = _hasConfiguredWallPicsAuth();
  final wallPicsBase = configuredWallPicsBase.isNotEmpty
      ? configuredWallPicsBase
      : hasWallPicsAuth
          ? 'https://backend.wallpics.app'
          : '';
  if (wallPicsBase.isNotEmpty) {
    sources.add(_DirectCatalogApiSource(baseUrl: wallPicsBase, headers: wallPicsHeaders));
  }

  final scraperBase = Env.normalize(Env.prismScraperApiBaseUrl).replaceAll(RegExp(r'/+$'), '');
  if (scraperBase.isNotEmpty && scraperBase != wallPicsBase) {
    sources.add(_DirectCatalogApiSource(baseUrl: scraperBase, headers: _baseDirectApiHeaders()));
  }
  return sources;
}

bool _hasConfiguredWallPicsAuth() {
  return Env.normalize(Env.wallPicsAuthHeader).isNotEmpty ||
      Env.normalize(Env.wallPicsBearerToken).isNotEmpty ||
      Env.normalize(Env.wallPicsXToken).isNotEmpty ||
      Env.normalize(Env.wallPicsXAuth).isNotEmpty ||
      Env.normalize(Env.wallPicsHhaa).isNotEmpty ||
      Env.normalize(Env.wallPicsExtraHeadersJson).isNotEmpty;
}

Map<String, String> _baseDirectApiHeaders() {
  return <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'User-Agent': 'PrismCatalogDirect/1.0',
  };
}

Map<String, String> _wallPicsApiHeaders() {
  final headers = _baseDirectApiHeaders();
  final rawAuthHeader = Env.normalize(Env.wallPicsAuthHeader);
  if (rawAuthHeader.isNotEmpty) {
    final separator = rawAuthHeader.indexOf(':');
    if (separator > 0) {
      final name = rawAuthHeader.substring(0, separator).trim();
      final value = rawAuthHeader.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        headers[name] = value;
      }
    } else {
      headers['Authorization'] = rawAuthHeader;
    }
  }
  final bearer = Env.normalize(Env.wallPicsBearerToken);
  if (bearer.isNotEmpty && !headers.containsKey('Authorization')) {
    headers['Authorization'] = bearer.startsWith('Bearer ') ? bearer : 'Bearer $bearer';
  }
  final xToken = Env.normalize(Env.wallPicsXToken);
  if (xToken.isNotEmpty) {
    headers['x-token'] = xToken;
  }
  final xAuth = Env.normalize(Env.wallPicsXAuth);
  if (xAuth.isNotEmpty) {
    headers['x-auth'] = xAuth;
  }
  final hhaa = Env.normalize(Env.wallPicsHhaa);
  if (hhaa.isNotEmpty) {
    headers['__hhaa__'] = hhaa;
  }
  final extraHeaders = Env.normalize(Env.wallPicsExtraHeadersJson);
  if (extraHeaders.isNotEmpty) {
    try {
      final decoded = jsonDecode(extraHeaders);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = _string(entry.key).trim();
          final value = _string(entry.value).trim();
          if (key.isNotEmpty && value.isNotEmpty) {
            headers[key] = value;
          }
        }
      }
    } catch (_) {
      // Ignore malformed optional headers and keep the standard auth fields.
    }
  }
  return headers;
}

Uri _directApiUri({
  required String baseUrl,
  required String endpoint,
  required int page,
  required String slug,
  required int pageSize,
}) {
  final uri = Uri.parse('$baseUrl$endpoint');
  final query = <String, String>{
    'paginated': '1',
    'page': '$page',
    'per_page': '$pageSize',
    'sortBy': 'recommended',
    'nsfwContent': '1',
  };
  final cleanSlug = slug.trim();
  if (cleanSlug.isNotEmpty && cleanSlug != 'for-you') {
    query['categorySlug'] = cleanSlug;
  }
  return uri.replace(queryParameters: query);
}

List<Map<String, dynamic>> _directPayloadItems(Object? payload) {
  final data = payload is Map ? payload['data'] : payload;
  if (data is List) {
    return data.whereType<Map>().map(_asMap).toList(growable: false);
  }
  final wallpapers = payload is Map ? payload['wallpapers'] : null;
  if (wallpapers is List) {
    return wallpapers.whereType<Map>().map(_asMap).toList(growable: false);
  }
  final items = payload is Map ? payload['items'] : null;
  if (items is List) {
    return items.whereType<Map>().map(_asMap).toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

int? _directPayloadLastPage(Object? payload) {
  if (payload is! Map) {
    return null;
  }
  final info = _asMap(payload['info']);
  return _int(info['last_page']) ?? _int(info['lastPage']) ?? _int(payload['last_page']) ?? _int(payload['lastPage']);
}

int _directPayloadItemCount(Object? payload, {required int page, required int pageSize, required int itemCount}) {
  if (payload is Map) {
    final info = _asMap(payload['info']);
    final explicit = _int(info['total']) ??
        _int(info['total_items']) ??
        _int(info['totalItems']) ??
        _int(info['item_count']) ??
        _int(payload['total']) ??
        _int(payload['item_count']);
    if (explicit != null && explicit > 0) {
      return explicit;
    }
  }
  final lastPage = _directPayloadLastPage(payload);
  if (lastPage == null || lastPage <= 0) {
    return ((page - 1) * pageSize) + itemCount;
  }
  if (page >= lastPage) {
    return ((page - 1) * pageSize) + itemCount;
  }
  return lastPage * pageSize;
}

Map<String, dynamic> _normalizeDirectApiItem(
  Map<String, dynamic> raw, {
  required String contentType,
  required String sourceBase,
  required String section,
  required String endpoint,
  required int page,
  required int index,
}) {
  final item = Map<String, dynamic>.from(raw);
  item['content_type'] = contentType;
  item['source'] = sourceBase;
  item['media_source'] = sourceBase;
  item['source_section'] = section;
  item['source_endpoint'] = endpoint;
  item['source_page'] = page;
  item['source_index'] = index;

  void setIfEmpty(String key, Object? value) {
    if (_string(item[key]).trim().isEmpty && value != null && _string(value).trim().isNotEmpty) {
      item[key] = value;
    }
  }

  switch (contentType) {
    case PrismCatalogDataSource.regularContentType:
      setIfEmpty('download_url', item['wallpaper']);
      setIfEmpty('preview_image', _firstString(<Object?>[item['hq_thumbnail'], item['static_thumbnail'], item['thumbnail']]));
      break;
    case PrismCatalogDataSource.liveContentType:
      setIfEmpty('download_url', _firstString(<Object?>[item['video_original '], item['video_original'], item['video']]));
      setIfEmpty('preview_image', _firstString(<Object?>[item['first_frame_thumbnail'], item['static_thumbnail'], item['thumbnail']]));
      break;
    case PrismCatalogDataSource.matchingContentType:
      _normalizeDirectPairList(item, fallbackRolePrefix: 'pair');
      break;
    case PrismCatalogDataSource.doubleContentType:
      _normalizeDirectDoublePair(item);
      break;
    case PrismCatalogDataSource.parallaxContentType:
      setIfEmpty('download_url', item['parallax_file']);
      setIfEmpty('preview_image', _firstParallaxLayerUrl(item) ?? item['thumbnail']);
      break;
    case PrismCatalogDataSource.profilePictureContentType:
      setIfEmpty('download_url', item['image']);
      setIfEmpty('preview_image', item['thumbnail']);
      break;
  }

  item['media_assets'] = _uniqueStrings(<String>[
    ..._strings(item['media_assets']),
    _string(item['download_url']),
    _string(item['preview_image']),
    _string(item['wallpaper']),
    _string(item['image']),
    _string(item['video_original ']),
    _string(item['video_original']),
    _string(item['video']),
    _string(item['parallax_file']),
    _string(item['thumbnail']),
    _string(item['static_thumbnail']),
    _string(item['first_frame_thumbnail']),
  ].where((value) => value.trim().isNotEmpty));
  return item;
}

void _normalizeDirectPairList(Map<String, dynamic> item, {required String fallbackRolePrefix}) {
  final rawPairs = _maps(item['paired_wallpapers']).isNotEmpty ? _maps(item['paired_wallpapers']) : _maps(item['wallpapers']);
  if (rawPairs.isEmpty) {
    return;
  }
  final pairs = <Map<String, dynamic>>[];
  final downloads = <String>[];
  final previews = <String>[];
  for (var index = 0; index < rawPairs.length; index++) {
    final row = rawPairs[index];
    final image = _firstString(<Object?>[row['download_url'], row['image'], row['wallpaper'], row['full_url'], row['url']]);
    final thumbnail = _firstString(<Object?>[row['thumbnail'], row['preview_url'], image]);
    pairs.add(<String, dynamic>{
      ...row,
      'role': _firstString(<Object?>[row['role'], '$fallbackRolePrefix_${index + 1}']),
      'image': image,
      'download_url': image,
      'thumbnail': thumbnail,
    });
    if (image.isNotEmpty) {
      downloads.add(image);
    }
    if (thumbnail.isNotEmpty) {
      previews.add(thumbnail);
    }
  }
  item['paired_wallpapers'] = pairs;
  item['paired_download_urls'] = _uniqueStrings(downloads);
  item['paired_preview_urls'] = _uniqueStrings(previews);
  if (downloads.isNotEmpty) {
    item['download_url'] = downloads.first;
  }
  if (previews.isNotEmpty) {
    item['preview_image'] = previews.first;
  }
}

void _normalizeDirectDoublePair(Map<String, dynamic> item) {
  if (_maps(item['paired_wallpapers']).isNotEmpty || _maps(item['wallpapers']).isNotEmpty) {
    _normalizeDirectPairList(item, fallbackRolePrefix: 'side');
    return;
  }
  final lockImage = _firstString(<Object?>[item['lock_screen_wallpaper'], item['lockScreenWallpaper']]);
  final homeImage = _firstString(<Object?>[item['wallpaper'], item['home_screen_wallpaper'], item['homeScreenWallpaper']]);
  final pairs = <Map<String, dynamic>>[];
  if (lockImage.isNotEmpty) {
    pairs.add(<String, dynamic>{
      'role': 'lock_screen',
      'image': lockImage,
      'download_url': lockImage,
      'thumbnail': _firstString(<Object?>[item['lock_screen_thumbnail'], item['thumbnail']]),
    });
  }
  if (homeImage.isNotEmpty) {
    pairs.add(<String, dynamic>{
      'role': 'home_screen',
      'image': homeImage,
      'download_url': homeImage,
      'thumbnail': _firstString(<Object?>[item['home_screen_thumbnail'], item['thumbnail']]),
    });
  }
  item['paired_wallpapers'] = pairs;
  item['paired_download_urls'] = _uniqueStrings(pairs.map((pair) => _string(pair['download_url'])));
  item['paired_preview_urls'] = _uniqueStrings(pairs.map((pair) => _string(pair['thumbnail'])));
  if (homeImage.isNotEmpty) {
    item['download_url'] = homeImage;
  } else if (lockImage.isNotEmpty) {
    item['download_url'] = lockImage;
  }
  setFirstNonEmpty(item, 'preview_image', <Object?>[item['thumbnail'], item['home_screen_thumbnail'], item['lock_screen_thumbnail']]);
}

String? _firstParallaxLayerUrl(Map<String, dynamic> item) {
  final config = _asMap(item['thumbnail_config']);
  for (final layer in _maps(config['layers'])) {
    final url = _string(layer['url']).trim();
    if (url.isNotEmpty) {
      return url;
    }
  }
  return null;
}

void setFirstNonEmpty(Map<String, dynamic> item, String key, Iterable<Object?> values) {
  if (_string(item[key]).trim().isNotEmpty) {
    return;
  }
  final value = _firstString(values.toList(growable: false));
  if (value.isNotEmpty) {
    item[key] = value;
  }
}


({int? width, int? height}) _normalizedCatalogSize({required String contentType, required int? width, required int? height}) {
  if (contentType != PrismCatalogDataSource.parallaxContentType || width == null || height == null) {
    return (width: width, height: height);
  }
  final longSide = width > height ? width : height;
  if (longSide >= 3840 || longSide <= 0) {
    return (width: width, height: height);
  }
  final scale = 3840 / longSide;
  return (width: (width * scale).round(), height: (height * scale).round());
}

List<_PrismItem> _dedupeItems(Iterable<_PrismItem> items) {
  final seenIds = <String>{};
  final seenUrls = <String>{};
  final deduped = <_PrismItem>[];
  for (final item in items) {
    final idKey = item.id.trim().isEmpty ? '' : '${item.contentType}:${item.id.trim()}';
    final urlKey = _firstString(<Object?>[item.downloadUrl, item.previewUrl, item.thumbnailUrl]).trim().toLowerCase();
    final allowSharedUrl = item.contentType == PrismCatalogDataSource.matchingContentType ||
        item.contentType == PrismCatalogDataSource.doubleContentType ||
        item.contentType == PrismCatalogDataSource.profilePictureContentType;
    if (idKey.isNotEmpty && !seenIds.add(idKey)) {
      continue;
    }
    if (!allowSharedUrl && urlKey.isNotEmpty && !seenUrls.add(urlKey)) {
      continue;
    }
    if (item.id.trim().isEmpty && urlKey.isEmpty) {
      continue;
    }
    deduped.add(item);
  }
  return deduped;
}

String _resolveCatalogUrl(Object? value, {required String sourceBase}) {
  final raw = _string(value).trim();
  if (raw.isEmpty) {
    return '';
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }

  if (!sourceBase.startsWith('http://') && !sourceBase.startsWith('https://')) {
    return raw;
  }
  final baseUri = Uri.tryParse(sourceBase);
  if (baseUri == null || !baseUri.hasScheme) {
    return raw;
  }
  if (raw.startsWith('//')) {
    return '${baseUri.scheme}:$raw';
  }
  if (raw.startsWith('/')) {
    return baseUri.replace(path: raw, query: null, fragment: null).toString();
  }
  return baseUri.resolve(raw).toString();
}


String _fastTileImageUrl(String rawUrl, {int width = 1920, int quality = 96}) {
  final source = rawUrl.trim();
  if (!_isProxyableCatalogImageUrl(source)) {
    return '';
  }
  final base = _workerMediaBaseUrl();
  if (base.isEmpty) {
    return '';
  }
  final endpoint = Uri.tryParse('$base/v1/media/image');
  if (endpoint == null) {
    return '';
  }
  return endpoint
      .replace(queryParameters: <String, String>{
        'src': source,
        'w': '$width',
        'q': '$quality',
      })
      .toString();
}

String _fastTileOrOriginal(String rawUrl, {int width = 1080, int quality = 90}) {
  final fastUrl = _fastTileImageUrl(rawUrl, width: width, quality: quality);
  return fastUrl.isNotEmpty ? fastUrl : rawUrl.trim();
}

String _fastVideoOrOriginal(String rawUrl) {
  final fastUrl = _fastVideoUrl(rawUrl);
  return fastUrl.isNotEmpty ? fastUrl : rawUrl.trim();
}

String _fastVideoUrl(String rawUrl) {
  final source = rawUrl.trim();
  if (!_isProxyableCatalogVideoUrl(source)) {
    return '';
  }
  final base = _workerMediaBaseUrl();
  if (base.isEmpty) {
    return '';
  }
  final extension = _catalogVideoExtension(source);
  final endpoint = Uri.tryParse('$base/v1/media/video.$extension');
  if (endpoint == null) {
    return '';
  }
  return endpoint.replace(queryParameters: <String, String>{'src': source}).toString();
}

String _workerMediaBaseUrl() {
  final apiBase = Env.normalize(Env.userStoreApiBaseUrl).replaceAll(RegExp(r'/+$'), '');
  if (apiBase.isNotEmpty) {
    return apiBase;
  }
  final catalogBase = Env.normalize(Env.prismCatalogBaseUrl).replaceAll(RegExp(r'/+$'), '');
  const catalogSuffix = '/v1/catalog';
  if (catalogBase.endsWith(catalogSuffix)) {
    return catalogBase.substring(0, catalogBase.length - catalogSuffix.length);
  }
  return '';
}

bool _isProxyableCatalogImageUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https') {
    return false;
  }
  if (uri.host.isEmpty) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.webp');
}

bool _isCatalogImageAssetUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return false;
  final uri = Uri.tryParse(raw);
  final src = uri?.queryParameters['src'];
  final path = src != null && src.trim().isNotEmpty
      ? (Uri.tryParse(src.trim())?.path.toLowerCase() ?? src.toLowerCase())
      : (uri?.path.toLowerCase() ?? raw.toLowerCase());
  return path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.png') ||
      path.endsWith('.webp') ||
      path.endsWith('.gif');
}

bool _isActualCatalogImageUrl(String value) => _isCatalogImageAssetUrl(value) && !_isCatalogPreviewAssetUrl(value);

bool _isCatalogPreviewAssetUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return false;
  final uri = Uri.tryParse(raw);
  final decoded = Uri.decodeComponent(<String>[
    uri?.path ?? raw,
    uri?.query ?? '',
  ].join('?')).toLowerCase();
  return decoded.contains('/preview') ||
      decoded.contains('/previews') ||
      decoded.contains('/thumbnail') ||
      decoded.contains('/thumb') ||
      decoded.contains('first_frame') ||
      decoded.contains('poster') ||
      decoded.contains('watermark');
}

bool _isProxyableCatalogVideoUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.endsWith('.mp4') || path.endsWith('.mov');
}

String _catalogVideoExtension(String value) {
  final path = Uri.tryParse(value.trim())?.path.toLowerCase() ?? value.toLowerCase();
  return path.endsWith('.mov') ? 'mov' : 'mp4';
}

bool _isFastPrefetchableUrl(String value) {
  final path = Uri.tryParse(value.trim())?.path.toLowerCase() ?? value.toLowerCase();
  return value.trim().isNotEmpty &&
      !path.endsWith('.mp4') &&
      !path.endsWith('.mov') &&
      !path.endsWith('.zip') &&
      !_isCatalogPreviewAssetUrl(value);
}

const Set<String> _blockedCatalogTerms = <String>{
  'desktop',
  'macbook',
  'computer',
  'monitor',
  'tablet',
  'ipad',
  'widescreen',
};

const Map<String, List<String>> _searchAliasesByToken = <String, List<String>>{
  'goku': <String>['son goku', 'kakarot', 'kakarotto'],
  'vegeta': <String>['prince vegeta'],
  'spiderman': <String>['spider man', 'spider-man', 'miles morales', 'peter parker'],
  'batman': <String>['bruce wayne', 'dark knight'],
  'naruto': <String>['uzumaki naruto', 'naruto uzumaki'],
  'luffy': <String>['monkey d luffy', 'monkey luffy'],
};

bool _isBlockedCatalogLabel(String value) {
  final normalized = _normalizeForSearch(value);
  if (normalized.isEmpty) {
    return false;
  }
  final compact = normalized.replaceAll(' ', '');
  return _blockedCatalogTerms.any((term) => normalized.split(' ').contains(term) || compact == term);
}

bool _isBlockedCatalogSearch(String normalizedQuery) {
  final tokens = normalizedQuery.split(' ').where((token) => token.isNotEmpty).toSet();
  return tokens.any(_blockedCatalogTerms.contains);
}

String _normalizeForSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

int _scoreSearchEntry(_SearchIndexEntry entry, String normalizedQuery) {
  return _scoreSearchFieldsWithAliases(
    normalizedQuery: normalizedQuery,
    name: entry.name,
    slug: entry.slug,
    categories: entry.categoryNames,
    categorySlugs: entry.categorySlugs,
    tags: entry.tags,
  );
}

int _scoreSearchFieldsWithAliases({
  required String normalizedQuery,
  required String name,
  required String slug,
  required Iterable<String> categories,
  required Iterable<String> categorySlugs,
  required Iterable<String> tags,
  String description = '',
}) {
  var best = 0;
  for (final query in _expandedSearchQueries(normalizedQuery)) {
    final score = _scoreSearchFields(
      normalizedQuery: query,
      name: name,
      slug: slug,
      categories: categories,
      categorySlugs: categorySlugs,
      tags: tags,
      description: description,
    );
    if (score > best) {
      best = score;
    }
  }
  return best;
}

List<String> _expandedSearchQueries(String normalizedQuery) {
  final seen = <String>{};
  final queries = <String>[];
  void add(String value) {
    final normalized = _normalizeForSearch(value);
    if (normalized.isNotEmpty && seen.add(normalized)) {
      queries.add(normalized);
    }
  }

  add(normalizedQuery);
  for (final token in normalizedQuery.split(' ')) {
    for (final alias in _searchAliasesByToken[token] ?? const <String>[]) {
      add(alias);
    }
  }
  return queries;
}

bool _containsSearchPhrase(String field, String query) {
  if (field == query) {
    return true;
  }
  return field.startsWith('$query ') || field.endsWith(' $query') || field.contains(' $query ');
}

bool _containsSearchToken(String field, String token) {
  return field.split(' ').any((fieldToken) => fieldToken == token);
}

bool _containsSearchTokenPrefix(String field, String token) {
  return field.split(' ').any((fieldToken) => fieldToken.startsWith(token));
}

int _scoreSearchFields({
  required String normalizedQuery,
  required String name,
  required String slug,
  required Iterable<String> categories,
  required Iterable<String> categorySlugs,
  required Iterable<String> tags,
  String description = '',
}) {
  final tokens = normalizedQuery.split(' ').where((token) => token.isNotEmpty).toList(growable: false);
  if (tokens.isEmpty) {
    return 0;
  }

  final normalizedName = _normalizeForSearch(name);
  final normalizedSlug = _normalizeForSearch(slug);
  final normalizedDescription = _normalizeForSearch(description);
  final normalizedCategories = categories.map(_normalizeForSearch).where((value) => value.isNotEmpty).toList();
  final normalizedCategorySlugs = categorySlugs.map(_normalizeForSearch).where((value) => value.isNotEmpty).toList();
  final normalizedTags = tags.map(_normalizeForSearch).where((value) => value.isNotEmpty).toList();
  final fields = <String>[
    normalizedName,
    normalizedSlug,
    normalizedDescription,
    ...normalizedCategories,
    ...normalizedCategorySlugs,
    ...normalizedTags,
  ].where((value) => value.isNotEmpty).toList(growable: false);
  if (_isBlockedCatalogLabel(name) || _isBlockedCatalogLabel(slug)) {
    return 0;
  }
  final compactQuery = normalizedQuery.replaceAll(' ', '');
  final compactFields = fields.map((value) => value.replaceAll(' ', '')).toList(growable: false);
  final singleToken = tokens.length == 1 ? tokens.first : null;
  final allowCompactMatch = compactQuery.length >= 4;
  if (normalizedName == normalizedQuery || normalizedSlug == normalizedQuery) {
    return 10000;
  }
  if (normalizedCategories.any((value) => value == normalizedQuery) ||
      normalizedCategorySlugs.any((value) => value == normalizedQuery)) {
    return 9000;
  }
  if (normalizedTags.any((value) => value == normalizedQuery)) {
    return 8000;
  }
  if (singleToken == null
      ? (normalizedName.startsWith(normalizedQuery) || normalizedSlug.startsWith(normalizedQuery))
      : (_containsSearchTokenPrefix(normalizedName, singleToken) || _containsSearchTokenPrefix(normalizedSlug, singleToken))) {
    return 7000;
  }
  if (singleToken == null
      ? (normalizedCategories.any((value) => value.startsWith(normalizedQuery)) ||
          normalizedCategorySlugs.any((value) => value.startsWith(normalizedQuery)) ||
          normalizedTags.any((value) => value.startsWith(normalizedQuery)))
      : (normalizedCategories.any((value) => _containsSearchTokenPrefix(value, singleToken)) ||
          normalizedCategorySlugs.any((value) => _containsSearchTokenPrefix(value, singleToken)) ||
          normalizedTags.any((value) => _containsSearchTokenPrefix(value, singleToken)))) {
    return 6000;
  }
  if (_containsSearchPhrase(normalizedName, normalizedQuery) ||
      _containsSearchPhrase(normalizedSlug, normalizedQuery) ||
      (allowCompactMatch && compactFields.any((value) => value.contains(compactQuery)))) {
    return 5000;
  }
  if (fields.any((value) => _containsSearchPhrase(value, normalizedQuery))) {
    return 4000;
  }
  if (singleToken != null) {
    if (fields.any((value) => _containsSearchToken(value, singleToken))) {
      return 3800;
    }
    if (singleToken.length >= 3 && fields.any((value) => _containsSearchTokenPrefix(value, singleToken))) {
      return 2600;
    }
    return 0;
  }
  if (tokens.length > 1 &&
      fields.any((value) => tokens.every((token) => _containsSearchToken(value, token) || _containsSearchPhrase(value, token)))) {
    return 3000;
  }

  return 0;
}

List<_RankedItemReference> _dedupeReferences(Iterable<_RankedItemReference> refs) {
  final seen = <String>{};
  final deduped = <_RankedItemReference>[];
  for (final ref in refs) {
    final key = '${ref.contentType}:${ref.id}';
    if (ref.id.trim().isEmpty || !seen.add(key)) {
      continue;
    }
    deduped.add(ref);
  }
  return deduped;
}

int _compareRankedReferences(_RankedItemReference a, _RankedItemReference b) {
  final scoreCompare = b.score.compareTo(a.score);
  if (scoreCompare != 0) {
    return scoreCompare;
  }
  return _compareNewestReferences(a, b);
}

int _compareNewestReferences(_RankedItemReference a, _RankedItemReference b) {
  final aCreated = a.createdAt?.millisecondsSinceEpoch ?? 0;
  final bCreated = b.createdAt?.millisecondsSinceEpoch ?? 0;
  final createdCompare = bCreated.compareTo(aCreated);
  if (createdCompare != 0) {
    return createdCompare;
  }
  return a.ordinal.compareTo(b.ordinal);
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

List<String> _uniqueStrings(Iterable<String> values) {
  final seen = <String>{};
  return <String>[
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
  ];
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
