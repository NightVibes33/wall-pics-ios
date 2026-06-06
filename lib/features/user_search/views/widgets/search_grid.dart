import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/widgets/home/wallpapers/loading.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/features/prism_catalog/data/prism_seed_media_store.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class SearchGrid extends StatefulWidget {
  const SearchGrid({super.key, required this.query});

  final String query;

  @override
  State<SearchGrid> createState() => _SearchGridState();
}

enum _SearchResultFilter { all, wallpapers, live, matching, spatial, profile }

class _SearchFilterSpec {
  const _SearchFilterSpec({required this.filter, required this.label, required this.icon});

  final _SearchResultFilter filter;
  final String label;
  final IconData icon;
}

class _SearchGridState extends State<SearchGrid> {
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();
  static const Duration _thumbnailPrecacheTimeout = Duration(seconds: 5);
  static const int _maxWarmImages = 420;
  static const int _maxWarmVideos = 96;
  static const List<_SearchFilterSpec> _filters = <_SearchFilterSpec>[
    _SearchFilterSpec(filter: _SearchResultFilter.all, label: 'All', icon: JamIcons.grid_f),
    _SearchFilterSpec(filter: _SearchResultFilter.wallpapers, label: 'Wallpapers', icon: JamIcons.picture_f),
    _SearchFilterSpec(filter: _SearchResultFilter.live, label: 'Live', icon: JamIcons.play_circle_f),
    _SearchFilterSpec(filter: _SearchResultFilter.matching, label: 'Matching', icon: JamIcons.pictures_f),
    _SearchFilterSpec(filter: _SearchResultFilter.spatial, label: '3D', icon: JamIcons.box_f),
    _SearchFilterSpec(filter: _SearchResultFilter.profile, label: 'PFP', icon: JamIcons.user_circle),
  ];

  final List<PrismFeedItem> _items = <PrismFeedItem>[];
  final Set<String> _prefetchedThumbnailUrls = <String>{};
  final Set<String> _prefetchedVideoUrls = <String>{};
  late Future<void> _initialLoad;
  _SearchResultFilter _activeFilter = _SearchResultFilter.all;

  int get _queryLength => widget.query.trim().length;

  @override
  void initState() {
    super.initState();
    _initialLoad = _load();
  }

  @override
  void didUpdateWidget(covariant SearchGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _items.clear();
      _activeFilter = _SearchResultFilter.all;
      _initialLoad = _load();
    }
  }

  Future<void> _load() async {
    final query = widget.query;
    try {
      final firstPage = await PrismCatalogDataSource.instance.search(query: query, refresh: true, scanFullIndex: false);
      final firstItems = firstPage.items.whereType<PrismFeedItem>().toList(growable: false);
      _replaceResults(query: query, incoming: firstItems, trackPage: 1);
      unawaited(_loadCompleteResults(query));
    } catch (_) {
      await _loadCompleteResults(query, trackPage: 1, allowRethrow: true);
    }
  }

  Future<void> _loadCompleteResults(String query, {int trackPage = 2, bool allowRethrow = false}) async {
    try {
      final page = await PrismCatalogDataSource.instance.searchAll(query: query);
      final incoming = page.items.whereType<PrismFeedItem>().toList(growable: false);
      if (_sameResultIds(incoming)) {
        return;
      }
      _replaceResults(query: query, incoming: incoming, trackPage: trackPage);
    } catch (_) {
      if (allowRethrow && _items.isEmpty) {
        rethrow;
      }
    }
  }

  bool _sameResultIds(List<PrismFeedItem> incoming) {
    if (_items.length != incoming.length) {
      return false;
    }
    for (var index = 0; index < incoming.length; index++) {
      if (_items[index].id != incoming[index].id) {
        return false;
      }
    }
    return true;
  }

  void _replaceResults({required String query, required List<PrismFeedItem> incoming, required int trackPage}) {
    if (!mounted || widget.query != query) {
      return;
    }
    setState(() {
      _items
        ..clear()
        ..addAll(incoming);
    });
    unawaited(_precacheMedia(incoming));
    _trackResultsLoaded(page: trackPage, result: _items.isEmpty ? EventResultValue.empty : EventResultValue.success);
  }

  void _trackResultsLoaded({required int page, required EventResultValue result}) {
    analytics.track(
      SearchResultsLoadedEvent(
        provider: SearchProviderValue.prismCatalog,
        queryLength: _queryLength,
        resultCount: _items.length,
        page: page,
        result: result,
      ),
    );
  }

  Future<void> _refresh() async {
    _refreshKey.currentState?.show();
    await _load();
  }

  String _catalogContentType(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) => wallpaper.aiMetadata?['catalogContentType']?.toString().trim() ?? '',
      wallhaven: (_, _) => '',
      pexels: (_, _) => '',
    );
  }

  bool _matchesFilter(FeedItemEntity item, _SearchResultFilter filter) {
    if (filter == _SearchResultFilter.all) {
      return true;
    }
    final contentType = _catalogContentType(item);
    return switch (filter) {
      _SearchResultFilter.wallpapers => contentType == PrismCatalogDataSource.regularContentType,
      _SearchResultFilter.live => contentType == PrismCatalogDataSource.liveContentType,
      _SearchResultFilter.matching => contentType == PrismCatalogDataSource.matchingContentType ||
          contentType == PrismCatalogDataSource.doubleContentType,
      _SearchResultFilter.spatial => contentType == PrismCatalogDataSource.parallaxContentType,
      _SearchResultFilter.profile => contentType == PrismCatalogDataSource.profilePictureContentType,
      _SearchResultFilter.all => true,
    };
  }

  List<FeedItemEntity> _rawItemsForFilter(_SearchResultFilter filter) {
    return _items.where((item) => _matchesFilter(item, filter)).toList(growable: false);
  }

  List<FeedItemEntity> _displayItemsForFilter(_SearchResultFilter filter) {
    final rawItems = _rawItemsForFilter(filter);
    if (filter == _SearchResultFilter.matching) {
      return WallpaperTile.matchingSideItemsForItems(rawItems);
    }
    return WallpaperTile.expandMatchingItemsForDisplay(rawItems);
  }

  int _countForFilter(_SearchResultFilter filter) {
    return _displayItemsForFilter(filter).length;
  }

  double _gridAspectRatio(List<FeedItemEntity> displayItems) {
    if (_activeFilter == _SearchResultFilter.profile) {
      return 1.0;
    }
    final sample = displayItems.take(12).toList(growable: false);
    if (sample.isEmpty) {
      return 0.5;
    }
    final profileCount = sample.where(WallpaperTile.isProfilePictureItem).length;
    return profileCount * 2 >= sample.length ? 1.0 : 0.5;
  }

  Future<void> _precacheMedia(Iterable<PrismFeedItem> items) async {
    final expandedItems = WallpaperTile.expandMatchingItemsForDisplay(items).toList(growable: false);
    await Future.wait<void>(<Future<void>>[
      _precacheThumbnails(expandedItems),
      _warmVideos(expandedItems),
    ]);
  }

  Future<void> _precacheThumbnails(Iterable<FeedItemEntity> items) async {
    final futures = <Future<void>>[];
    var scheduled = 0;
    for (final item in items) {
      if (scheduled >= _maxWarmImages) {
        break;
      }
      final poster = WallpaperTile.posterUrlForItem(item).trim();
      final url = poster.isNotEmpty ? poster : item.thumbnailUrl.trim();
      if (url.isEmpty || PrismSeedMediaStore.instance.hasUrlSync(url) || !_prefetchedThumbnailUrls.add(url)) {
        continue;
      }
      scheduled += 1;
      futures.add(
        precacheImage(CachedNetworkImageProvider(url), context)
            .timeout(_thumbnailPrecacheTimeout)
            .catchError((Object _) {}),
      );
    }
    await Future.wait<void>(futures);
  }

  Future<void> _warmVideos(Iterable<FeedItemEntity> items) async {
    final futures = <Future<void>>[];
    var scheduled = 0;
    for (final item in items) {
      if (scheduled >= _maxWarmVideos) {
        break;
      }
      final videoUrl = WallpaperTile.videoUrlForItem(item).trim();
      if (videoUrl.isEmpty || PrismSeedMediaStore.instance.hasUrlSync(videoUrl) || !_prefetchedVideoUrls.add(videoUrl)) {
        continue;
      }
      scheduled += 1;
      futures.add(
        DefaultCacheManager().downloadFile(videoUrl).timeout(const Duration(seconds: 24)).then((_) {}).catchError((Object _) {}),
      );
    }
    await Future.wait<void>(futures);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialLoad,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _items.isEmpty) {
          return const LoadingCards();
        }
        if (snapshot.hasError && _items.isEmpty) {
          return _SearchLoadState(
            refreshKey: _refreshKey,
            onRefresh: _refresh,
            title: "Can't load results.",
            action: 'Pull to retry.',
          );
        }
        if (_items.isEmpty) {
          return _SearchLoadState(
            refreshKey: _refreshKey,
            onRefresh: _refresh,
            title: 'No results found.',
            action: 'Try another search.',
          );
        }

        final displayItems = _displayItemsForFilter(_activeFilter);
        final totalCount = _countForFilter(_SearchResultFilter.all);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SearchResultHeader(query: widget.query, resultCount: totalCount),
            _SearchFilterBar(
              filters: _filters,
              activeFilter: _activeFilter,
              countForFilter: _countForFilter,
              onSelected: (filter) => setState(() => _activeFilter = filter),
            ),
            Expanded(
              child: RefreshIndicator(
                key: _refreshKey,
                backgroundColor: Theme.of(context).primaryColor,
                onRefresh: _refresh,
                child: displayItems.isEmpty
                    ? _EmptyFilteredResults(filter: _activeFilter)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(5, 6, 5, 120),
                        cacheExtent: 16000,
                        itemCount: displayItems.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: MediaQuery.of(context).orientation == Orientation.portrait ? 3 : 5,
                          childAspectRatio: _gridAspectRatio(displayItems),
                          mainAxisSpacing: 0,
                          crossAxisSpacing: 0,
                        ),
                        itemBuilder: (context, index) {
                          return WallpaperTile(
                            item: displayItems[index],
                            index: index,
                            galleryItems: displayItems,
                            playVideoPreview: true,
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchResultHeader extends StatelessWidget {
  const _SearchResultHeader({required this.query, required this.resultCount});

  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              query.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontFamily: 'Satoshi', fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: foreground.withValues(alpha: 0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                '$resultCount',
                style: TextStyle(color: foreground, fontFamily: 'Satoshi', fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFilterBar extends StatelessWidget {
  const _SearchFilterBar({
    required this.filters,
    required this.activeFilter,
    required this.countForFilter,
    required this.onSelected,
  });

  final List<_SearchFilterSpec> filters;
  final _SearchResultFilter activeFilter;
  final int Function(_SearchResultFilter filter) countForFilter;
  final ValueChanged<_SearchResultFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final spec = filters[index];
          final selected = spec.filter == activeFilter;
          final count = countForFilter(spec.filter);
          return _SearchFilterChip(spec: spec, selected: selected, count: count, onTap: () => onSelected(spec.filter));
        },
      ),
    );
  }
}

class _SearchFilterChip extends StatelessWidget {
  const _SearchFilterChip({required this.spec, required this.selected, required this.count, required this.onTap});

  final _SearchFilterSpec spec;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? foreground : foreground.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? foreground : foreground.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(spec.icon, size: 17, color: selected ? Theme.of(context).primaryColor : foreground),
            const SizedBox(width: 7),
            Text(
              spec.label,
              style: TextStyle(
                color: selected ? Theme.of(context).primaryColor : foreground,
                fontFamily: 'Satoshi',
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (count > 0) ...<Widget>[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: selected ? Theme.of(context).primaryColor.withValues(alpha: 0.7) : foreground.withValues(alpha: 0.55),
                  fontFamily: 'Satoshi',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyFilteredResults extends StatelessWidget {
  const _EmptyFilteredResults({required this.filter});

  final _SearchResultFilter filter;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _SearchResultFilter.wallpapers => 'wallpapers',
      _SearchResultFilter.live => 'live photos',
      _SearchResultFilter.matching => 'matching sets',
      _SearchResultFilter.spatial => '3D wallpapers',
      _SearchResultFilter.profile => 'PFPs',
      _SearchResultFilter.all => 'results',
    };
    return ListView(
      children: <Widget>[
        const SizedBox(height: 190),
        Center(
          child: Text(
            'No $label found.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.72),
              fontFamily: 'Satoshi',
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchLoadState extends StatelessWidget {
  const _SearchLoadState({required this.refreshKey, required this.onRefresh, required this.title, required this.action});

  final GlobalKey<RefreshIndicatorState> refreshKey;
  final RefreshCallback onRefresh;
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      key: refreshKey,
      onRefresh: onRefresh,
      child: ListView(
        children: <Widget>[
          const SizedBox(height: 220),
          Center(
            child: Column(
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontFamily: 'Satoshi',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  action,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.62),
                    fontFamily: 'Satoshi',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
