import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class WallpaperTile extends StatelessWidget {
  const WallpaperTile({super.key, required this.item, required this.index, this.memCacheHeight, this.crossAxisCount});

  final FeedItemEntity item;
  final int index;
  final int? memCacheHeight;

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

  static double aspectRatioForItem(FeedItemEntity item) {
    return isProfilePictureItem(item) ? 1.0 : 0.5;
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
    final image = CachedNetworkImage(
      imageUrl: item.thumbnailUrl,
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
          context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(item)));
        },
        child: isProfilePictureItem(item)
            ? Padding(padding: const EdgeInsets.all(6), child: ClipOval(child: image))
            : image,
      ),
    );
  }
}
