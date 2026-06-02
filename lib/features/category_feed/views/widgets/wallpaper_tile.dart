import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/widgets/common/autoplay_video_preview.dart';
import 'package:Prism/core/wallpaper/wallpaper_core.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_gallery_store.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class WallpaperTile extends StatelessWidget {
  const WallpaperTile({
    super.key,
    required this.item,
    required this.index,
    this.memCacheHeight,
    this.crossAxisCount,
    this.galleryItems,
  });

  final FeedItemEntity item;
  final int index;
  final int? memCacheHeight;
  final List<FeedItemEntity>? galleryItems;

  /// When null, uses the app's standard grid (3 columns portrait, 5 landscape).
  final int? crossAxisCount;

  AnalyticsSurfaceValue get _surface => AnalyticsSurfaceValue.homeWallpaperGrid;

  String get _sourceContext => 'home_wallpaper_grid_tile';

  static bool isProfilePictureItem(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) =>
          wallpaper.aiMetadata?['catalogContentType'] == PrismCatalogDataSource.profilePictureContentType,
      wallhaven: (_, _) => false,
      pexels: (_, _) => false,
    );
  }

  static bool isMatchingSetItem(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) {
        final contentType = wallpaper.aiMetadata?['catalogContentType'];
        return contentType == PrismCatalogDataSource.matchingContentType ||
            contentType == PrismCatalogDataSource.doubleContentType;
      },
      wallhaven: (_, _) => false,
      pexels: (_, _) => false,
    );
  }

  static List<String> pairedImageUrlsForItem(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) {
        if (!isMatchingSetItem(item)) return const <String>[];
        return _stringList(wallpaper.aiMetadata?['catalogPairedDownloadUrls']);
      },
      wallhaven: (_, _) => const <String>[],
      pexels: (_, _) => const <String>[],
    );
  }

  static List<String> pairedPreviewUrlsForItem(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) {
        if (!isMatchingSetItem(item)) return const <String>[];
        final previews = _stringList(wallpaper.aiMetadata?['catalogPairedPreviewUrls']);
        return previews.isNotEmpty ? previews : pairedImageUrlsForItem(item);
      },
      wallhaven: (_, _) => const <String>[],
      pexels: (_, _) => const <String>[],
    );
  }

  static List<FeedItemEntity> matchingSideItemsForItems(Iterable<FeedItemEntity> items) {
    return items.expand(matchingSideItemsForItem).toList(growable: false);
  }

  static List<FeedItemEntity> expandMatchingItemsForDisplay(Iterable<FeedItemEntity> items) {
    final displayItems = <FeedItemEntity>[];
    for (final item in items) {
      final sideItems = matchingSideItemsForItem(item);
      if (sideItems.isEmpty) {
        displayItems.add(item);
      } else {
        displayItems.addAll(sideItems);
      }
    }
    return displayItems;
  }

  static List<FeedItemEntity> matchingSideItemsForItem(FeedItemEntity item) {
    return item.when(
      prism: (id, wallpaper) {
        if (!isMatchingSetItem(item)) return const <FeedItemEntity>[];
        final fullUrls = _stringList(wallpaper.aiMetadata?['catalogPairedDownloadUrls']);
        if (fullUrls.length < 2) return const <FeedItemEntity>[];
        final previewUrls = pairedPreviewUrlsForItem(item);
        return <FeedItemEntity>[
          for (var index = 0; index < fullUrls.length; index++)
            _matchingSideItem(
              parentId: id,
              wallpaper: wallpaper,
              fullUrl: fullUrls[index],
              previewUrl: index < previewUrls.length ? previewUrls[index] : fullUrls[index],
              index: index,
            ),
        ];
      },
      wallhaven: (_, _) => const <FeedItemEntity>[],
      pexels: (_, _) => const <FeedItemEntity>[],
    );
  }

  static FeedItemEntity _matchingSideItem({
    required String parentId,
    required PrismWallpaper wallpaper,
    required String fullUrl,
    required String previewUrl,
    required int index,
  }) {
    final sideId = '$parentId-side-${index + 1}';
    final metadata = Map<String, Object?>.of(wallpaper.aiMetadata ?? const <String, Object?>{});
    metadata
      ..remove('catalogPairedWallpapers')
      ..remove('catalogPairedPreviewUrls')
      ..remove('catalogPairedDownloadUrls')
      ..['catalogContentType'] = PrismCatalogDataSource.regularContentType
      ..['catalogParentContentType'] = PrismCatalogDataSource.matchingContentType
      ..['catalogMatchingSetId'] = parentId
      ..['catalogMatchingSideIndex'] = index
      ..['catalogPreviewUrl'] = previewUrl;
    final thumb = previewUrl.trim().isNotEmpty ? previewUrl.trim() : fullUrl.trim();
    final sideWallpaper = PrismWallpaper(
      core: WallpaperCore(
        id: sideId,
        source: WallpaperSource.prism,
        fullUrl: fullUrl.trim(),
        thumbnailUrl: thumb,
        resolution: wallpaper.core.resolution,
        sizeBytes: wallpaper.core.sizeBytes,
        authorName: wallpaper.core.authorName,
        authorEmail: wallpaper.core.authorEmail,
        authorPhoto: wallpaper.core.authorPhoto,
        authorId: wallpaper.core.authorId,
        category: wallpaper.core.category,
        createdAt: wallpaper.core.createdAt,
        width: wallpaper.core.width,
        height: wallpaper.core.height,
        favourites: wallpaper.core.favourites,
      ),
      collections: wallpaper.collections,
      review: wallpaper.review,
      tags: wallpaper.tags,
      aiMetadata: metadata,
      isStreakExclusive: wallpaper.isStreakExclusive,
      requiredStreakDays: wallpaper.requiredStreakDays,
      streakShopCoinCost: wallpaper.streakShopCoinCost,
      remoteStoreDocumentId: null,
    );
    return FeedItemEntity.prism(id: sideId, wallpaper: sideWallpaper);
  }

  static String animatedPreviewUrlForItem(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) {
        final candidates = <String>[
          _metadataString(wallpaper.aiMetadata, 'catalogThumbnailVideoUrl'),
          _metadataString(wallpaper.aiMetadata, 'catalogVideoUrl'),
          wallpaper.fullUrl.trim(),
        ];
        for (final candidate in candidates) {
          if (candidate.isNotEmpty && _isVideoUrl(candidate)) return candidate;
        }
        return '';
      },
      wallhaven: (_, _) => '',
      pexels: (_, _) => '',
    );
  }

  static String posterUrlForItem(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) {
        final candidates = <String>[
          _metadataString(wallpaper.aiMetadata, 'catalogStaticThumbnailUrl'),
          _metadataString(wallpaper.aiMetadata, 'catalogFirstFrameThumbnailUrl'),
          _metadataString(wallpaper.aiMetadata, 'catalogPreviewUrl'),
          wallpaper.thumbnailUrl.trim(),
          wallpaper.fullUrl.trim(),
        ];
        for (final candidate in candidates) {
          if (candidate.isNotEmpty && !_isVideoUrl(candidate)) return candidate;
        }
        return '';
      },
      wallhaven: (_, wallpaper) => wallpaper.thumbnailUrl.trim(),
      pexels: (_, wallpaper) => wallpaper.thumbnailUrl.trim(),
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    final seen = <String>{};
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList(growable: false);
  }

  static String _metadataString(Object? metadata, String key) {
    if (metadata is! Map) return '';
    return metadata[key]?.toString().trim() ?? '';
  }

  static bool _isVideoUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.mp4') || path.endsWith('.mov');
  }

  static double aspectRatioForItem(FeedItemEntity item) {
    return isProfilePictureItem(item) ? 1.0 : 0.5;
  }

  Widget _cachedTileImage(
    BuildContext context,
    String url, {
    required int cacheWidth,
    required int cacheHeight,
  }) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.medium,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (ctx, _) => ColoredBox(color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
      errorWidget: (ctx, _, _) => ColoredBox(color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
    );
  }

  Widget _matchingSetTile(
    BuildContext context,
    List<String> urls, {
    required int cacheWidth,
    required int cacheHeight,
  }) {
    final halfCacheWidth = (cacheWidth / 2).ceil();
    final sides = urls.take(2).toList(growable: false);
    return Row(
      children: <Widget>[
        Expanded(
          child: _cachedTileImage(
            context,
            sides[0],
            cacheWidth: halfCacheWidth,
            cacheHeight: cacheHeight,
          ),
        ),
        const SizedBox(width: 2, child: ColoredBox(color: Colors.black)),
        Expanded(
          child: _cachedTileImage(
            context,
            sides[1],
            cacheWidth: halfCacheWidth,
            cacheHeight: cacheHeight,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = crossAxisCount ?? (MediaQuery.orientationOf(context) == Orientation.portrait ? 3 : 5);
    final width = (MediaQuery.sizeOf(context).width / columns).toInt();
    final aspectRatio = aspectRatioForItem(item);
    final height = memCacheHeight ?? (width / aspectRatio).ceil();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheWidth = (width * pixelRatio).ceil();
    final cacheHeight = (height * pixelRatio).ceil();
    final pairedImageUrls = pairedPreviewUrlsForItem(item);
    final animatedPreviewUrl = animatedPreviewUrlForItem(item);
    final image = pairedImageUrls.length >= 2
        ? _matchingSetTile(context, pairedImageUrls, cacheWidth: cacheWidth, cacheHeight: cacheHeight)
        : animatedPreviewUrl.isNotEmpty
            ? AutoplayVideoPreview(
                videoUrl: animatedPreviewUrl,
                posterUrl: posterUrlForItem(item),
                fit: BoxFit.cover,
              )
            : _cachedTileImage(context, item.thumbnailUrl, cacheWidth: cacheWidth, cacheHeight: cacheHeight);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
        highlightColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
        onTap: () {
          unawaited(
            analytics.track(
              SurfaceActionTappedEvent(
                surface: _surface,
                action: AnalyticsActionValue.tileOpened,
                sourceContext: _sourceContext,
                itemType: ItemTypeValue.wallpaper,
                itemId: item.id,
                index: index,
              ),
            ),
          );
          if (isMatchingSetItem(item)) {
            final sideItems = matchingSideItemsForItem(item);
            if (sideItems.isNotEmpty) {
              WallpaperDetailGalleryStore.setFromFeedItems(items: sideItems, index: 0);
              context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(sideItems.first)));
              return;
            }
          }
          final items = galleryItems ?? <FeedItemEntity>[item];
          WallpaperDetailGalleryStore.setFromFeedItems(items: items, index: index);
          context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(item)));
        },
        child: isProfilePictureItem(item)
            ? Padding(padding: const EdgeInsets.all(6), child: ClipOval(child: image))
            : image,
      ),
    );
  }
}
