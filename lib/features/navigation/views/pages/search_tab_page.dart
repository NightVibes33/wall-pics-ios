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
  late Future<List<FeedItemEntity>> _liveItemsFuture;

  @override
  void initState() {
    super.initState();
    _liveItemsFuture = _loadLiveItems();
  }

  Future<List<FeedItemEntity>> _loadLiveItems() async {
    final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(
      category: const CategoryEntity(
        name: 'Live Photos',
        source: WallpaperSource.prism,
        searchType: CategorySearchType.nonSearch,
        image: '',
        image2: '',
        catalogSlug: 'for-you',
        catalogContentType: PrismCatalogDataSource.liveContentType,
      ),
      refresh: true,
    );
    final seen = <String>{};
    return <FeedItemEntity>[
      for (final item in page?.items ?? const <FeedItemEntity>[])
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
                          (context, index) => WallpaperTile(item: items[index], index: index, galleryItems: items),
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
