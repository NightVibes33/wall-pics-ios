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
  late Future<List<FeedItemEntity>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
  }

  @override
  void didUpdateWidget(covariant _CategoryFeedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.catalogSlug != widget.category.catalogSlug ||
        oldWidget.category.catalogContentType != widget.category.catalogContentType) {
      _itemsFuture = _loadItems();
    }
  }

  Future<List<FeedItemEntity>> _loadItems() async {
    final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(category: widget.category, refresh: true);
    return _uniqueItems(page?.items ?? const <FeedItemEntity>[]);
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
      _itemsFuture = _loadItems();
    });
    await _itemsFuture;
  }

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
    return FutureBuilder<List<FeedItemEntity>>(
      future: _itemsFuture,
      builder: (context, state) {
        final rawItems = state.data ?? const <FeedItemEntity>[];
        final items = WallpaperTile.expandMatchingItemsForDisplay(rawItems);
        if (state.connectionState == ConnectionState.waiting && items.isEmpty) {
          return const LoadingCards();
        }
        if (state.hasError && items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Spacer(),
                Center(child: Text("Can't load this catalog. Pull to retry.")),
                Spacer(),
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
        return RefreshIndicator(
          onRefresh: _refresh,
          child: GridView.builder(
            cacheExtent: 16000,
            padding: const EdgeInsets.fromLTRB(0, 5, 0, 140),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: _gridAspectRatio(items),
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
            ),
            itemBuilder: (context, index) {
              return WallpaperTile(
                item: items[index],
                index: index,
                galleryItems: items,
                playVideoPreview: true,
              );
            },
          ),
        );
      },
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
