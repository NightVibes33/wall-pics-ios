import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/widgets/premiumBanners/premiumBanner.dart';
import 'package:Prism/data/collections/provider/collectionsWithoutProvider.dart' as CData;
import 'package:Prism/features/category_feed/views/category_feed_bloc_adapter.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CollectionsGrid extends StatefulWidget {
  @override
  _CollectionsGridState createState() => _CollectionsGridState();
}

enum _DiscoverTileKind { collection, category }

final class _DiscoverTileData {
  const _DiscoverTileData({
    required this.kind,
    required this.name,
    required this.thumb1,
    required this.thumb2,
    required this.isPremium,
  });

  final _DiscoverTileKind kind;
  final String name;
  final String thumb1;
  final String thumb2;
  final bool isPremium;
}

String _discoverTileSemanticLabel(_DiscoverTileData tile) {
  final String trimmed = tile.name.trim();
  if (tile.kind == _DiscoverTileKind.category) {
    if (trimmed.isEmpty) {
      return 'Category';
    }
    return 'Category, $trimmed';
  }
  if (trimmed.isEmpty) {
    return tile.isPremium ? 'Premium collection' : 'Collection';
  }
  if (tile.isPremium) {
    return 'Premium collection, $trimmed';
  }
  return 'Collection, $trimmed';
}

/// Decodes network thumbs near on-screen size to reduce memory and GPU upload cost.
ImageProvider? _resizeCachedThumb(BuildContext context, String url, double logicalW, double logicalH) {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final double dpr = MediaQuery.devicePixelRatioOf(context);
  final int w = (logicalW * dpr).round().clamp(1, 4096);
  final int h = (logicalH * dpr).round().clamp(1, 4096);
  return ResizeImage(CachedNetworkImageProvider(trimmed), width: w, height: h);
}

const double _kCollectionsTitleBlockHeight = 40;
const double _kCollectionsTitleImageGap = 6;
const double _kCollectionsGridChildAspectRatio = 0.56;

class _CollectionTileSkeleton extends StatefulWidget {
  const _CollectionTileSkeleton({required this.cellWidth, required this.base, required this.highlight});

  final double cellWidth;
  final Color base;
  final Color highlight;

  @override
  State<_CollectionTileSkeleton> createState() => _CollectionTileSkeletonState();
}

class _CollectionTileSkeletonState extends State<_CollectionTileSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Color?> _shimmer;

  void _attachColors() {
    _shimmer = ColorTween(
      begin: widget.base,
      end: widget.highlight,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _attachColors();
    _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _CollectionTileSkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.base != oldWidget.base || widget.highlight != oldWidget.highlight) {
      _attachColors();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color fallback = Theme.of(context).colorScheme.surfaceContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: _kCollectionsTitleBlockHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: _shimmer,
              builder: (BuildContext context, Widget? child) {
                return Container(width: widget.cellWidth * 0.65, height: 13, color: _shimmer.value ?? fallback);
              },
            ),
          ),
        ),
        const SizedBox(height: _kCollectionsTitleImageGap),
        Expanded(
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (BuildContext context, Widget? child) {
              return ColoredBox(color: _shimmer.value ?? fallback);
            },
          ),
        ),
      ],
    );
  }
}

class _CollectionsGridState extends State<CollectionsGrid> with TickerProviderStateMixin {
  Future<void> _handleCollectionTap({required bool isPremium, required String collectionName}) async {
    _openCollection(collectionName);
  }

  void _openCollection(String collectionName) {
    context.router.push(CollectionViewRoute(collectionName: collectionName.trim().toLowerCase()));
  }

  Future<void> refreshList() async {
    await CData.getCollections();
  }

  @override
  Widget build(BuildContext context) {
    final List<Object?> rawCollections =
        CData.collections?.whereType<Object?>().toList(growable: false) ?? const <Object?>[];
    final bool isLoading = rawCollections.isEmpty;

    Map<String, dynamic> asMap(Object? raw) {
      if (raw is Map<String, dynamic>) {
        return raw;
      }
      if (raw is Map) {
        return raw.cast<String, dynamic>();
      }
      return <String, dynamic>{};
    }

    final List<_DiscoverTileData> discoverTiles = isLoading
        ? const <_DiscoverTileData>[]
        : <_DiscoverTileData>[
            ...rawCollections.map((raw) {
              final collection = asMap(raw);
              return _DiscoverTileData(
                kind: _DiscoverTileKind.collection,
                name: collection['name']?.toString() ?? '',
                thumb1: collection['thumb1']?.toString() ?? '',
                thumb2: collection['thumb2']?.toString() ?? '',
                isPremium: collection['premium'] == true,
              );
            }),
            ...context
                .categoryChoiceList(listen: false)
                .map(
                  (choice) => _DiscoverTileData(
                    kind: _DiscoverTileKind.category,
                    name: choice.name?.trim() ?? '',
                    thumb1: choice.image?.trim() ?? '',
                    thumb2: choice.image2?.trim() ?? choice.image?.trim() ?? '',
                    isPremium: false,
                  ),
                ),
          ];
    final int itemCount = isLoading ? 8 : discoverTiles.length;
    const double gridSpacing = 8;
    const EdgeInsets gridPadding = EdgeInsets.fromLTRB(5, 4, 5, 4);

    final ThemeData theme = Theme.of(context);
    final double viewportW = MediaQuery.sizeOf(context).width;
    final double cellWidth = (viewportW - gridPadding.horizontal - gridSpacing) / 2;
    final double cellHeight = cellWidth / _kCollectionsGridChildAspectRatio;
    final double imageDecodeHeight = (cellHeight - _kCollectionsTitleBlockHeight - _kCollectionsTitleImageGap).clamp(
      48.0,
      4000.0,
    );

    Widget buildCollectionCard(_DiscoverTileData? tile) {
      final bool loading = tile == null;
      final bool isPremium = tile?.isPremium ?? false;
      final ColorScheme scheme = Theme.of(context).colorScheme;

      if (loading) {
        final Widget tileBody = Material(
          color: Colors.transparent,
          child: _CollectionTileSkeleton(
            cellWidth: cellWidth,
            base: scheme.surfaceContainer,
            highlight: scheme.surfaceContainerHigh,
          ),
        );
        return Semantics(label: 'Loading', enabled: false, excludeSemantics: true, child: tileBody);
      }

      final _DiscoverTileData data = tile;
      final String rawThumb1 = data.thumb1.trim();
      final String rawThumb2 = data.thumb2.trim();
      final String thumbUrl = rawThumb1.isNotEmpty ? rawThumb1 : rawThumb2;
      final ImageProvider? thumbImage = _resizeCachedThumb(context, thumbUrl, cellWidth, imageDecodeHeight);
      final String trimmedName = data.name.trim();
      final String displayTitle = trimmedName.isNotEmpty
          ? trimmedName
          : (data.kind == _DiscoverTileKind.category ? 'Category' : 'Collection');

      void onTapTile() {
        if (data.kind == _DiscoverTileKind.collection) {
          unawaited(_handleCollectionTap(isPremium: isPremium, collectionName: data.name));
          return;
        }
        final encodedName = Uri.encodeComponent(data.name);
        context.router.push(CollectionViewRoute(collectionName: 'category:$encodedName'));
      }

      final Widget content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: _kCollectionsTitleBlockHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface) ??
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
            ),
          ),
          const SizedBox(height: _kCollectionsTitleImageGap),
          Expanded(
            child: PremiumBanner(
              comparator: !isPremium,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  image: thumbImage != null ? DecorationImage(image: thumbImage, fit: BoxFit.cover) : null,
                ),
                child: thumbImage != null ? null : const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );

      final Widget tileBody = Material(
        color: Colors.transparent,
        child: InkWell(
          splashColor: scheme.secondary.withValues(alpha: 0.3),
          highlightColor: scheme.secondary.withValues(alpha: 0.1),
          onTap: onTapTile,
          child: content,
        ),
      );

      return Semantics(button: true, label: _discoverTileSemanticLabel(data), excludeSemantics: true, child: tileBody);
    }

    return RefreshIndicator(
      onRefresh: refreshList,
      color: theme.colorScheme.primary,
      backgroundColor: theme.primaryColor,
      edgeOffset: MediaQuery.paddingOf(context).top,
      child: GridView.builder(
        padding: gridPadding,
        itemCount: itemCount,
        physics: AlwaysScrollableScrollPhysics(parent: ScrollConfiguration.of(context).getScrollPhysics(context)),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: _kCollectionsGridChildAspectRatio,
          mainAxisSpacing: gridSpacing,
          crossAxisSpacing: gridSpacing,
        ),
        itemBuilder: (BuildContext context, int index) {
          if (isLoading) {
            return buildCollectionCard(null);
          }
          return buildCollectionCard(discoverTiles[index]);
        },
      ),
    );
  }
}
