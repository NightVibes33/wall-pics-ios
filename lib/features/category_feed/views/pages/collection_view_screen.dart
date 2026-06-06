import 'package:Prism/core/widgets/home/core/headingChipBar.dart';
import 'package:Prism/core/widgets/home/wallpapers/loading.dart';
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
  const CollectionViewScreen({super.key, required this.collectionName});

  final String collectionName;

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
      backgroundColor: Theme.of(context).primaryColor,
      appBar: PreferredSize(
        preferredSize: const Size(double.infinity, 55),
        child: HeadingChipBar(current: title),
      ),
      body: _isCategoryView
          ? _CategoryFeedContent(category: _categoryEntityFromPayload(_decodedCategoryPayload))
          : _buildCollectionContent(),
    );
  }

  Widget _buildCollectionContent() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          'Open a category from Home or Browse.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CategoryFeedContent extends StatefulWidget {
  const _CategoryFeedContent({required this.category});

  final CategoryEntity category;

  @override
  State<_CategoryFeedContent> createState() => _CategoryFeedContentState();
}

class _CategoryFeedContentState extends State<_CategoryFeedContent> {
  final ScrollController _scrollController = ScrollController();
  final List<FeedItemEntity> _rawItems = <FeedItemEntity>[];
  int _generation = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
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
      _loadInitial();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingInitial || _loadingMore || !_hasMore) {
      return;
    }
    final remaining = _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    if (remaining < 1800) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    final generation = ++_generation;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
      _rawItems.clear();
    });
    try {
      final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(category: widget.category, refresh: true);
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
    if (_loadingInitial || _loadingMore || !_hasMore) {
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

  Future<void> _refresh() => _loadInitial();

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
      return const LoadingCards();
    }
    if (_error != null && items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const <Widget>[
            SizedBox(height: 220),
            Center(child: Text("Can't load this catalog. Pull to retry.")),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const <Widget>[
            SizedBox(height: 220),
            Center(child: Text('No wallpapers loaded. Pull to retry.')),
          ],
        ),
      );
    }

    final columns = MediaQuery.of(context).orientation == Orientation.portrait ? 3 : 5;
    final loadingTileCount = _loadingMore ? columns : 0;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        controller: _scrollController,
        cacheExtent: 18000,
        padding: const EdgeInsets.fromLTRB(0, 5, 0, 140),
        itemCount: items.length + loadingTileCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: _gridAspectRatio(items),
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        ),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          return WallpaperTile(
            item: items[index],
            index: index,
            galleryItems: items,
            playVideoPreview: true,
          );
        },
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
