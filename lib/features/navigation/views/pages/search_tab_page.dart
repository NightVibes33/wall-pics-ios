import 'dart:async';

import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

@RoutePage()
class SearchTabPage extends StatefulWidget {
  const SearchTabPage({super.key});

  @override
  State<SearchTabPage> createState() => _SearchTabPageState();
}

class _SearchTabPageState extends State<SearchTabPage> {
  static const CategoryEntity _liveCategory = CategoryEntity(
    name: 'Live Photos',
    source: WallpaperSource.prism,
    searchType: CategorySearchType.nonSearch,
    image: '',
    image2: '',
    catalogSlug: 'for-you',
    catalogContentType: PrismCatalogDataSource.liveContentType,
  );

  late Future<List<FeedItemEntity>> _liveItemsFuture;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _liveItemsFuture = _loadLiveItems();
  }

  Future<List<FeedItemEntity>> _loadLiveItems() async {
    final generation = ++_loadGeneration;
    final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(category: _liveCategory, refresh: true);
    final firstItems = _uniqueItems(page?.items ?? const <FeedItemEntity>[]);
    unawaited(_loadCompleteLiveItems(generation));
    return firstItems;
  }

  Future<void> _loadCompleteLiveItems(int generation) async {
    try {
      final page = await PrismCatalogDataSource.instance.fetchFullCategoryFeed(category: _liveCategory);
      final fullItems = _uniqueItems(page?.items ?? const <FeedItemEntity>[]);
      if (!mounted || generation != _loadGeneration || fullItems.isEmpty) {
        return;
      }
      setState(() {
        _liveItemsFuture = Future<List<FeedItemEntity>>.value(fullItems);
      });
    } catch (_) {
      // The already-rendered first page remains usable.
    }
  }

  List<FeedItemEntity> _uniqueItems(Iterable<FeedItemEntity> items) {
    final seen = <String>{};
    return <FeedItemEntity>[
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }

  Future<void> _refresh() async {
    setState(() {
      _liveItemsFuture = _loadLiveItems();
    });
    await _liveItemsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<FeedItemEntity>>(
          future: _liveItemsFuture,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <FeedItemEntity>[];
            return RefreshIndicator(
              color: Colors.white,
              backgroundColor: Colors.black,
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: 16000,
                slivers: <Widget>[
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(18, 22, 18, 18),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Live Photos',
                        style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 34, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting && items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    )
                  else if (items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No live wallpapers loaded. Pull to retry.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 140),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.5,
                          mainAxisSpacing: 0,
                          crossAxisSpacing: 0,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => WallpaperTile(item: items[index], index: index, galleryItems: items, playVideoPreview: true),
                          childCount: items.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
