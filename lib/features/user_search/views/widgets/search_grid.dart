import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/core/widgets/home/wallpapers/loading.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
  late Future<void> _initialLoad;
  _SearchResultFilter _activeFilter = _SearchResultFilter.all;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _currentPage = 1;

  int get _queryLength => widget.query.trim().length;

  @override
  void initState() {
    super.initState();
    _initialLoad = _load(refresh: true);
  }

  @override
  void didUpdateWidget(covariant SearchGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _items.clear();
      _hasMore = false;
      _currentPage = 1;
      _activeFilter = _SearchResultFilter.all;
      _initialLoad = _load(refresh: true);
    }
  }

  Future<void> _load({required bool refresh}) async {
    final page = await PrismCatalogDataSource.instance.search(query: widget.query, refresh: refresh);
    final incoming = page.items.whereType<PrismFeedItem>().toList(growable: false);
    if (!mounted) {
      return;
    }
    setState(() {
      if (refresh) {
        _items
          ..clear()
          ..addAll(incoming);
        _currentPage = 1;
      } else {
        final byKey = <String, PrismFeedItem>{
          for (final item in _items) _resultKey(item): item,
        };
        for (final item in incoming) {
          byKey[_resultKey(item)] = item;
        }
        _items
          ..clear()
          ..addAll(byKey.values);
        _currentPage += 1;
      }
      _hasMore = page.hasMore;
    });
    unawaited(_precacheThumbnails(incoming));
    _trackResultsLoaded(page: _currentPage, result: _items.isEmpty ? EventResultValue.empty : EventResultValue.success);
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

  String _resultKey(PrismFeedItem item) {
    final fullUrl = item.wallpaper.fullUrl.trim();
    final thumbnailUrl = item.thumbnailUrl.trim();
    if (fullUrl.isNotEmpty) {
      return fullUrl.toLowerCase();
    }
    if (thumbnailUrl.isNotEmpty) {
      return thumbnailUrl.toLowerCase();
    }
    return item.id;
  }

  Future<void> _refresh() async {
    _refreshKey.currentState?.show();
    await _load(refresh: true);
  }

  Future<void> _requestNextPage() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    analytics.track(
      SearchPaginationRequestedEvent(
        provider: SearchProviderValue.prismCatalog,
        queryLength: _queryLength,
        page: _currentPage + 1,
      ),
    );
    try {
      await _load(refresh: false);
    } catch (error, stackTrace) {
      logger.e('Failed to load Prism search results page.', error: error, stackTrace: stackTrace);
      _trackResultsLoaded(page: _currentPage + 1, result: EventResultValue.failure);
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
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

  Future<void> _precacheThumbnails(Iterable<PrismFeedItem> items) async {
    final futures = <Future<void>>[];
    for (final item in WallpaperTile.expandMatchingItemsForDisplay(items)) {
      final url = item.thumbnailUrl.trim();
      if (url.isEmpty || !_prefetchedThumbnailUrls.add(url)) {
        continue;
      }
      futures.add(
        precacheImage(CachedNetworkImageProvider(url), context)
            .timeout(_thumbnailPrecacheTimeout)
            .catchError((Object _) {}),
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
                child: NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 240) {
                      unawaited(_requestNextPage());
                    }
                    return false;
                  },
                  child: displayItems.isEmpty
                      ? _EmptyFilteredResults(filter: _activeFilter)
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(5, 6, 5, 120),
                          cacheExtent: 12000,
                          itemCount: displayItems.length + (_hasMore ? 1 : 0),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: MediaQuery.of(context).orientation == Orientation.portrait ? 3 : 5,
                            childAspectRatio: _gridAspectRatio(displayItems),
                            mainAxisSpacing: 0,
                            crossAxisSpacing: 0,
                          ),
                          itemBuilder: (context, index) {
                            if (index >= displayItems.length) {
                              return _SearchMoreTile(loading: _loadingMore, onPressed: _requestNextPage);
                            }
                            return WallpaperTile(item: displayItems[index], index: index, galleryItems: displayItems);
                          },
                        ),
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

class _SearchMoreTile extends StatelessWidget {
  const _SearchMoreTile({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.28)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: EdgeInsets.zero,
        ),
        child: loading ? Loader() : const Icon(JamIcons.chevrons_down, size: 26),
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
