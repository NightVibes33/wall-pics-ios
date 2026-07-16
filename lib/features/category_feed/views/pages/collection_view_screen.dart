import 'dart:async';

import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/global/categoryMenu.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

@RoutePage()
class CollectionViewScreen extends StatefulWidget {
  const CollectionViewScreen({
    super.key,
    required this.collectionName,
    this.initialItems = const <FeedItemEntity>[],
  });

  final String collectionName;
  final List<FeedItemEntity> initialItems;

  @override
  State<CollectionViewScreen> createState() => _CollectionViewScreenState();
}

class _CollectionViewScreenState extends State<CollectionViewScreen> {
  bool get _isCategoryView => widget.collectionName.startsWith('category:');

  String get _decodedCategoryPayload {
    final encoded = widget.collectionName.substring('category:'.length);
    return Uri.decodeComponent(encoded).trim();
  }

  String get _decodedCategoryName {
    final payload = _decodedCategoryPayload;
    if (payload.contains('|')) {
      final parts = payload.split('|');
      return parts.isNotEmpty ? parts.last.trim() : payload;
    }
    return payload;
  }

  CategoryMenu _categoryChoiceFromPayload(String payload) {
    if (payload.contains('|')) {
      final parts = payload.split('|');
      final contentType = parts.isNotEmpty ? parts[0].trim() : '';
      final slug = parts.length > 1 ? parts[1].trim() : '';
      final name = parts.length > 2 && parts[2].trim().isNotEmpty ? parts[2].trim() : _decodedCategoryName;
      return CategoryMenu(
        name: name,
        provider: 'Prism',
        image: '',
        image2: '',
        catalogSlug: slug,
        catalogContentType: contentType,
      );
    }
    return CategoryMenu(name: _decodedCategoryName, provider: 'Prism', image: '', image2: '');
  }

  CategoryEntity _categoryEntityFromPayload(String payload) {
    final choice = _categoryChoiceFromPayload(payload);
    return CategoryEntity(
      name: choice.name ?? _decodedCategoryName,
      source: WallpaperSource.prism,
      searchType: CategorySearchType.nonSearch,
      image: choice.image ?? '',
      image2: choice.image2 ?? '',
      catalogSlug: choice.catalogSlug?.trim().isNotEmpty == true ? choice.catalogSlug : 'for-you',
      catalogContentType: choice.catalogContentType?.trim().isNotEmpty == true
          ? choice.catalogContentType
          : PrismCatalogDataSource.regularContentType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isCategoryView ? _decodedCategoryName.capitalize() : widget.collectionName.capitalize();
    return Scaffold(
      backgroundColor: const Color(0xFF07080B),
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xFF11151D), Color(0xFF0A0B0F), Color(0xFF060608)],
                    stops: <double>[0.0, 0.26, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    children: <Widget>[
                      Material(
                        color: const Color(0xFF101217),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => context.router.maybePop(),
                          child: const SizedBox(
                            width: 52,
                            height: 52,
                            child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 19),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Satoshi',
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _isCategoryView ? 'Fresh picks from this Prism collection.' : 'Browse curated Prism collections.',
                              style: const TextStyle(
                                color: Colors.white70,
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
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Color(0xFF152539), Color(0xFF0D1219), Color(0xFF08090C)],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFF7DC7FF)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _isCategoryView
                                ? 'Open the full feed and pull for a fresh reload when you want a different mix.'
                                : 'Use Home and Browse to open a category and jump into a full collection feed.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontFamily: 'Satoshi',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _isCategoryView
                      ? _CategoryFeedContent(
                          category: _categoryEntityFromPayload(_decodedCategoryPayload),
                          initialItems: widget.initialItems,
                        )
                      : _buildCollectionContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionContent() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          'Open a category from Home or Browse.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CategoryFeedContent extends StatefulWidget {
  const _CategoryFeedContent({required this.category, required this.initialItems});

  final CategoryEntity category;
  final List<FeedItemEntity> initialItems;

  @override
  State<_CategoryFeedContent> createState() => _CategoryFeedContentState();
}

class _CategoryFeedContentState extends State<_CategoryFeedContent> {
  final ScrollController _scrollController = ScrollController();
  final List<FeedItemEntity> _rawItems = <FeedItemEntity>[];
  int _generation = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _synchronizing = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialItems.isNotEmpty) {
      _rawItems.addAll(_uniqueItems(widget.initialItems));
      _loadingInitial = false;
      unawaited(_synchronizeInitialPage());
    } else {
      _loadInitial(refresh: true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CategoryFeedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.catalogSlug != widget.category.catalogSlug ||
        oldWidget.category.catalogContentType != widget.category.catalogContentType) {
      _loadInitial(refresh: true);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingInitial || _loadingMore || _synchronizing || !_hasMore) {
      return;
    }
    final remaining = _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    if (remaining < 1800) {
      _loadMore();
    }
  }

  Future<void> _synchronizeInitialPage() async {
    _synchronizing = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    try {
      final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(
        category: widget.category,
        refresh: true,
      );
      if (!mounted) return;
      setState(() {
        _appendUnique(page?.items ?? const <FeedItemEntity>[]);
        _hasMore = page?.hasMore ?? false;
        _synchronizing = false;
      });
    } catch (_) {
      _synchronizing = false;
    }
  }

  Future<void> _loadInitial({bool refresh = false}) async {
    final generation = ++_generation;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
      _rawItems.clear();
    });
    try {
      final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(category: widget.category, refresh: refresh);
      if (!mounted || generation != _generation) return;
      setState(() {
        _rawItems.addAll(_uniqueItems(page?.items ?? const <FeedItemEntity>[]));
        _hasMore = page?.hasMore ?? false;
        _loadingInitial = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _hasMore = false;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingInitial || _loadingMore || _synchronizing || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(category: widget.category, refresh: false);
      if (!mounted) return;
      setState(() {
        _appendUnique(page?.items ?? const <FeedItemEntity>[]);
        _hasMore = page?.hasMore ?? false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  List<FeedItemEntity> _uniqueItems(Iterable<FeedItemEntity> items) {
    final seen = <String>{};
    return <FeedItemEntity>[
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }

  void _appendUnique(Iterable<FeedItemEntity> items) {
    final seen = _rawItems.map((item) => item.id).toSet();
    for (final item in items) {
      if (seen.add(item.id)) {
        _rawItems.add(item);
      }
    }
  }

  Future<void> _refresh() => _loadInitial(refresh: true);

  double _gridAspectRatio(List<FeedItemEntity> items) {
    if (widget.category.catalogContentType == PrismCatalogDataSource.profilePictureContentType) {
      return 1.0;
    }
    final sample = items.take(18).toList(growable: false);
    if (sample.isEmpty) {
      return 0.5;
    }
    final profileCount = sample.where(WallpaperTile.isProfilePictureItem).length;
    return profileCount * 2 >= sample.length ? 1.0 : 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final items = WallpaperTile.expandMatchingItemsForDisplay(_rawItems);
    if (_loadingInitial && items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null && items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 140),
          children: const <Widget>[
            SizedBox(height: 140),
            _FeedStateCard(title: "Can't load this collection.", subtitle: 'Pull down to retry.'),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 140),
          children: const <Widget>[
            SizedBox(height: 140),
            _FeedStateCard(title: 'No wallpapers loaded.', subtitle: 'Pull down to retry.'),
          ],
        ),
      );
    }

    final columns = MediaQuery.of(context).orientation == Orientation.portrait ? 3 : 5;
    final loadingTileCount = _loadingMore ? columns : 0;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF050506),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: GridView.builder(
          controller: _scrollController,
          cacheExtent: MediaQuery.sizeOf(context).height * 0.75,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 160),
          itemCount: items.length + loadingTileCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: _gridAspectRatio(items),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
            }
            return WallpaperTile(
              item: items[index],
              index: index,
              galleryItems: items,
              playVideoPreview: false,
            );
          },
        ),
      ),
    );
  }
}

class _FeedStateCard extends StatelessWidget {
  const _FeedStateCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101217),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Satoshi',
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'Satoshi',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

extension _StringExtension on String {
  String capitalize() {
    if (isEmpty) {
      return this;
    }
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
