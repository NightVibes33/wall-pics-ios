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
  static const int _catalogShardSize = 100;
  static const Duration _metadataTimeout = Duration(seconds: 10);
  static const Duration _pageTimeout = Duration(seconds: 8);
  static const Duration _searchIndexTimeout = Duration(seconds: 25);
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

  final Map<String, Future<_PrismCatalogPage>> _pageFutures = <String, Future<_PrismCatalogPage>>{};
  final Map<String, Future<List<_PrismItem>>> _compactCatalogFutures = <String, Future<List<_PrismItem>>>{};
  final Map<String, int> _offsets = <String, int>{};
  Future<List<Map<String, dynamic>>>? _categoryRowsFuture;
  Future<Map<String, Map<String, List<String>>>>? _categoryIdsFuture;
  Future<Map<String, Map<String, int>>>? _itemLocationsFuture;
  Future<List<_SearchIndexEntry>>? _searchIndexFuture;

  bool supports(CategoryEntity category) {
    final slug = category.catalogSlug?.trim();
    final type = category.catalogContentType?.trim();
    return slug != null && slug.isNotEmpty && type != null && _catalogPagePrefixesByContentType.containsKey(type);
  }

  Future<CategoryFeedPage?> fetchCategoryFeed({required CategoryEntity category, required bool refresh}) async {
    if (!supports(category)) return null;

    final contentType = category.catalogContentType!.trim();
    final slug = category.catalogSlug!.trim();
    final scope = _scope(slug: slug, contentType: contentType);

    if (slug == 'for-you') {
      return _fetchSequentialPageFeed(contentType: contentType, scope: scope, refresh: refresh);
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

  Future<CategoryFeedPage> fetchHomePage({required bool refresh}) {
    return _fetchSequentialPageFeed(
      contentType: regularContentType,
      scope: _scope(slug: 'for-you', contentType: regularContentType),
      refresh: refresh,
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

  Future<CategoryFeedPage> search({required String query, required bool refresh}) async {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty || _isBlockedCatalogSearch(normalizedQuery)) {
      return const CategoryFeedPage(items: <FeedItemEntity>[], hasMore: false, nextCursor: null);
    }

    final scope = 'search.$normalizedQuery';
    final start = refresh ? 0 : (_offsets[scope] ?? 0);
    final needed = start + _pageSize;
    final rankedRefs = await _rankedCategoryReferences(normalizedQuery);

    if (rankedRefs.length < needed) {
      var ordinal = rankedRefs.length;
      final searchIndex = await _loadSearchIndex();
      for (final entry in searchIndex) {
        if (!_catalogPagePrefixesByContentType.containsKey(entry.contentType)) {
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
      rankedRefs.sort(_compareRankedReferences);
    }

    final deduped = _dedupeReferences(rankedRefs);
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

  Future<PrismWallpaper?> fetchById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    final locationsByContentType = await _loadItemLocations();
    for (final contentType in _catalogPagePrefixesByContentType.keys) {
      final page = locationsByContentType[contentType]?[trimmed];
      if (page == null) {
        continue;
      }
      final item = (await _loadCatalogPage(contentType, page)).byId(trimmed);
      if (item != null) return item.toWallpaper();
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
          _isBlockedCatalogLabel(name) ||
          _isBlockedCatalogLabel(slug) ||
          _isBlockedCatalogLabel(_string(row['parent_slug']))) {
        continue;
      }
      final score = _scoreSearchFields(
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
  }) async {
    Object? remoteError;
    final remoteBase = _remoteCatalogBaseUrl;
    if (remoteBase.isNotEmpty) {
      final base = remoteBase.endsWith('/') ? remoteBase.substring(0, remoteBase.length - 1) : remoteBase;
      try {
        final response = await http.get(Uri.parse('$base/$fileName')).timeout(timeout);
        if (response.statusCode >= 200 && response.statusCode < 300 && _looksLikeJson(response.body)) {
          return response.body;
        }
        remoteError = StateError('Catalog request failed for $fileName with HTTP ${response.statusCode}');
      } catch (error) {
        remoteError = error;
      }
    }

    try {
      return await rootBundle.loadString('assets/catalog/$fileName');
    } catch (bundleError) {
      if (!allowGeneratedFallback) {
        throw StateError('Missing required catalog asset $fileName: ${remoteError ?? bundleError}');
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
      throw StateError('Missing catalog asset $fileName: ${remoteError ?? bundleError}');
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
    if (_catalogPagePrefixesByContentType.containsKey(type)) {
      return type;
    }
    return _numericCategoryTypes[type] ?? regularContentType;
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
    required this.mediaAssetUrls,
    required this.pairedWallpapers,
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
  final List<String> mediaAssetUrls;
  final List<Map<String, dynamic>> pairedWallpapers;
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
    final pairedWallpapers = _maps(json['paired_wallpapers']);
    final pairedDownloadUrls = pairedWallpapers
        .map((wallpaper) => _firstString(<Object?>[
              url(wallpaper['download_url']),
              url(wallpaper['wallpaper']),
              url(wallpaper['image']),
              url(wallpaper['full_url']),
              url(wallpaper['url']),
            ]))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final derivedPairedPreviewUrls = pairedWallpapers
        .map((wallpaper) => _firstString(<Object?>[
              url(wallpaper['download_url']),
              url(wallpaper['wallpaper']),
              url(wallpaper['image']),
              url(wallpaper['full_url']),
              url(wallpaper['url']),
              url(wallpaper['thumbnail']),
              url(wallpaper['static_thumbnail']),
            ]))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final pairedDisplayUrls = pairedDownloadUrls.isNotEmpty ? pairedDownloadUrls : derivedPairedPreviewUrls;
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
    final fullImage = _firstString(<Object?>[
      wallpaper,
      image,
      catalogDownload,
      sticker,
      parallaxFile,
    ]);
    final thumb = _firstString(<Object?>[
      firstFrameThumbnail,
      ...pairedDisplayUrls,
      fullImage,
      wallpaper,
      image,
      sticker,
      parallaxFile,
      staticThumbnail,
      hqThumbnail,
      thumbnail,
    ]);
    final staticThumb = contentType == PrismCatalogDataSource.liveContentType
        ? _firstString(<Object?>[
            firstFrameThumbnail,
            staticThumbnail,
            hqThumbnail,
            thumb,
          ])
        : _firstString(<Object?>[
            thumb,
            fullImage,
            staticThumbnail,
            hqThumbnail,
            firstFrameThumbnail,
          ]);
    final preview = _firstString(<Object?>[
      firstFrameThumbnail,
      ...pairedDisplayUrls,
      fullImage,
      wallpaper,
      image,
      sticker,
      parallaxFile,
      thumb,
      staticThumbnail,
      hqThumbnail,
      thumbnail,
    ]);
    final displayOnlyContent = contentType == PrismCatalogDataSource.diyTemplateContentType ||
        contentType == PrismCatalogDataSource.liveDiyTemplateContentType;
    return _PrismItem(
      id: _string(json['id']),
      name: _string(json['name']),
      slug: _string(json['slug']),
      description: _string(json['description']),
      contentType: contentType,
      width: _int(json['width']),
      height: _int(json['height']),
      downloadUrl: displayOnlyContent
          ? _firstString(<Object?>[template, wallpaper, image, fullImage, preview, thumb])
          : (contentType == PrismCatalogDataSource.matchingContentType ||
                contentType == PrismCatalogDataSource.doubleContentType)
          ? _firstString(<Object?>[catalogDownload, ...pairedDisplayUrls, wallpaper, image])
          : contentType == PrismCatalogDataSource.liveContentType
          ? _firstString(<Object?>[catalogDownload, video, wallpaper])
          : _firstString(<Object?>[catalogDownload, wallpaper, image, video]),
      previewUrl: preview,
      thumbnailUrl: thumb,
      staticThumbnailUrl: staticThumb,
      firstFrameThumbnailUrl: firstFrameThumbnail,
      videoUrl: video,
      thumbnailVideoUrl: url(json['thumbnail_video']),
      templateUrl: template.isNotEmpty ? template : catalogDownload,
      mediaAssetUrls: mediaAssetUrls,
      pairedWallpapers: pairedWallpapers,
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
        ? _firstString(<Object?>[firstFrameThumbnailUrl, staticThumbnailUrl, thumbnailUrl, previewUrl, full])
        : (contentType == PrismCatalogDataSource.matchingContentType ||
                contentType == PrismCatalogDataSource.doubleContentType)
            ? _firstString(<Object?>[...pairedDownloadUrls, thumbnailUrl, full, previewUrl])
            : displayOnlyContent
                ? _firstString(<Object?>[previewUrl, staticThumbnailUrl, thumbnailUrl, full])
                : _firstString(<Object?>[full, thumbnailUrl, previewUrl, staticThumbnailUrl]);
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
        'catalogMediaAssetUrls': mediaAssetUrls,
        'catalogPairedWallpapers': pairedWallpapers,
        'catalogPairedPreviewUrls': pairedPreviewUrls,
        'catalogPairedDownloadUrls': pairedDownloadUrls,
        'catalogIsPremium': false,
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

const Set<String> _blockedCatalogTerms = <String>{
  'desktop',
  'macbook',
  'computer',
  'monitor',
  'tablet',
  'ipad',
  'widescreen',
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
  return _scoreSearchFields(
    normalizedQuery: normalizedQuery,
    name: entry.name,
    slug: entry.slug,
    categories: entry.categoryNames,
    categorySlugs: entry.categorySlugs,
    tags: entry.tags,
  );
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
  if (normalizedName.startsWith(normalizedQuery) || normalizedSlug.startsWith(normalizedQuery)) {
    return 7000;
  }
  if (normalizedCategories.any((value) => value.startsWith(normalizedQuery)) ||
      normalizedCategorySlugs.any((value) => value.startsWith(normalizedQuery)) ||
      normalizedTags.any((value) => value.startsWith(normalizedQuery))) {
    return 6000;
  }
  if (normalizedName.contains(normalizedQuery) ||
      normalizedSlug.contains(normalizedQuery) ||
      compactFields.any((value) => compactQuery.isNotEmpty && value.contains(compactQuery))) {
    return 5000;
  }
  if (fields.any((value) => value.contains(normalizedQuery))) {
    return 4000;
  }
  if (tokens.length > 1 && fields.any((value) => tokens.every(value.contains))) {
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
