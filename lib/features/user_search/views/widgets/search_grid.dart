import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/core/widgets/home/wallpapers/loading.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/logger/logger.dart';
import 'package:flutter/material.dart';

class SearchGrid extends StatefulWidget {
  const SearchGrid({super.key, required this.query});

  final String query;

  @override
  State<SearchGrid> createState() => _SearchGridState();
}

class _SearchGridState extends State<SearchGrid> {
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();
  final List<PrismFeedItem> _items = <PrismFeedItem>[];
  late Future<void> _initialLoad;
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
        final byId = <String, PrismFeedItem>{for (final item in _items) item.id: item};
        for (final item in incoming) {
          byId[item.id] = item;
        }
        _items
          ..clear()
          ..addAll(byId.values);
        _currentPage += 1;
      }
      _hasMore = page.hasMore;
    });
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
      SearchPaginationRequestedEvent(provider: SearchProviderValue.prismCatalog, queryLength: _queryLength, page: _currentPage + 1),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialLoad,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _items.isEmpty) {
          return const LoadingCards();
        }
        if (snapshot.hasError && _items.isEmpty) {
          return RefreshIndicator(
            key: _refreshKey,
            onRefresh: _refresh,
            child: ListView(
              children: const [
                SizedBox(height: 220),
                Center(child: Text("Can't load Prism results.")),
              ],
            ),
          );
        }
        if (_items.isEmpty) {
          return RefreshIndicator(
            key: _refreshKey,
            onRefresh: _refresh,
            child: ListView(
              children: const [
                SizedBox(height: 220),
                Center(child: Text('No Prism results found.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
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
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(5, 4, 5, 120),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).orientation == Orientation.portrait ? 3 : 5,
                childAspectRatio: 0.5,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
              ),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return MaterialButton(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onPressed: _loadingMore ? null : _requestNextPage,
                    child: _loadingMore ? Loader() : const Text('See more'),
                  );
                }
                return WallpaperTile(item: _items[index], index: index);
              },
            ),
          ),
        );
      },
    );
  }
}
