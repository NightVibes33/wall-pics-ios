import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/analytics/trackers/content_load_tracker.dart';
import 'package:Prism/core/analytics/trackers/scroll_milestone_tracker.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/core/widgets/home/wallpapers/seeMoreButton.dart';
import 'package:Prism/features/category_feed/biz/bloc/category_feed_bloc.j.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/category_feed_bloc_adapter.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/theme_mode/views/theme_mode_bloc_utils.dart';
import 'package:Prism/logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WallpaperGrid extends StatefulWidget {
  const WallpaperGrid({super.key});

  @override
  State<WallpaperGrid> createState() => _WallpaperGridState();
}

class _WallpaperGridState extends State<WallpaperGrid> {
  static const int _initialPrecacheCount = 24;
  static const int _lookAheadPrecacheCount = 72;
  static const Duration _thumbnailPrecacheTimeout = Duration(seconds: 3);

  final GlobalKey<RefreshIndicatorState> refreshHomeKey = GlobalKey<RefreshIndicatorState>();
  final ScrollMilestoneTracker _scrollMilestoneTracker = ScrollMilestoneTracker();
  final ContentLoadTracker _contentLoadTracker = ContentLoadTracker();
  final Set<String> _prefetchedThumbnailUrls = <String>{};

  bool seeMoreLoader = false;
  int _lastLoggedSubWallsCount = -1;
  String? _readyInitialBatchKey;
  String? _loadingInitialBatchKey;
  String? _lastLookAheadBatchKey;

  @override
  void initState() {
    super.initState();
    _contentLoadTracker.start();
  }

  Future<void> refreshList() async {
    refreshHomeKey.currentState?.show();
    _contentLoadTracker.start();
    _scrollMilestoneTracker.reset();
    await context.categoryChangeWallpaperFuture(context.categorySelectedChoice(listen: false), "r");
  }

  Future<void> _triggerSeeMore({required bool hasMore, required int currentItemCount}) async {
    if (seeMoreLoader || !hasMore) {
      return;
    }
    setState(() {
      seeMoreLoader = true;
    });
    logger.d("[WallpaperGrid] see more triggered", fields: <String, Object?>{"currentItems": currentItemCount});
    try {
      await context.categoryChangeWallpaperFuture(context.categorySelectedChoice(listen: false), "s");
    } finally {
      if (mounted) {
        setState(() {
          seeMoreLoader = false;
        });
      }
    }
  }

  void _prepareThumbnails(BuildContext context, List<PrismFeedItem> items) {
    if (items.isEmpty) {
      return;
    }
    _ensureInitialBatchCached(context, items);
    _scheduleLookAheadPrecache(context, items);
  }

  bool _initialBatchReady(List<PrismFeedItem> items) {
    final key = _batchKey(items, _initialPrecacheCount);
    return key.isEmpty || _readyInitialBatchKey == key;
  }

  void _ensureInitialBatchCached(BuildContext context, List<PrismFeedItem> items) {
    final key = _batchKey(items, _initialPrecacheCount);
    if (key.isEmpty || _readyInitialBatchKey == key || _loadingInitialBatchKey == key) {
      return;
    }
    _loadingInitialBatchKey = key;
    final urls = _thumbnailUrls(items.take(_initialPrecacheCount));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _precacheThumbnailUrls(context, urls, timeout: _thumbnailPrecacheTimeout);
      if (!mounted) {
        return;
      }
      setState(() {
        _readyInitialBatchKey = key;
        _loadingInitialBatchKey = null;
      });
    });
  }

  void _scheduleLookAheadPrecache(BuildContext context, List<PrismFeedItem> items) {
    final key = _batchKey(items, _lookAheadPrecacheCount);
    if (key.isEmpty || _lastLookAheadBatchKey == key) {
      return;
    }
    _lastLookAheadBatchKey = key;
    final urls = _thumbnailUrls(items.take(_lookAheadPrecacheCount));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_precacheThumbnailUrls(context, urls, timeout: _thumbnailPrecacheTimeout));
    });
  }

  Future<void> _precacheThumbnailUrls(BuildContext context, Iterable<String> urls, {required Duration timeout}) async {
    final futures = <Future<void>>[];
    for (final url in urls) {
      if (!_prefetchedThumbnailUrls.add(url)) {
        continue;
      }
      futures.add(
        precacheImage(CachedNetworkImageProvider(url), context)
            .timeout(timeout)
            .catchError((Object _) {}),
      );
    }
    await Future.wait<void>(futures);
  }

  String _batchKey(List<PrismFeedItem> items, int count) {
    return items.take(count).map((item) => item.id).join('|');
  }

  List<String> _thumbnailUrls(Iterable<PrismFeedItem> items) {
    return items
        .map((item) => item.thumbnailUrl.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final CategoryFeedState state = context.watch<CategoryFeedBloc>().state;
    final List<PrismFeedItem> subWalls = state.items.whereType<PrismFeedItem>().toList(growable: false);

    if (_lastLoggedSubWallsCount != subWalls.length) {
      _lastLoggedSubWallsCount = subWalls.length;
      logger.d("[WallpaperGrid] build", fields: <String, Object?>{"items": subWalls.length, "hasMore": state.hasMore});
    }
    if (subWalls.isNotEmpty) {
      _prepareThumbnails(context, subWalls);
    }
    final initialBatchReady = subWalls.isNotEmpty && _initialBatchReady(subWalls);
    final showSkeletonTiles = subWalls.isEmpty || !initialBatchReady;

    if (subWalls.isNotEmpty && initialBatchReady) {
      _contentLoadTracker.success(
        itemCount: subWalls.length,
        onSuccess: ({required int loadTimeMs, int? itemCount}) async {
          await analytics.track(
            SurfaceContentLoadedEvent(
              surface: AnalyticsSurfaceValue.homeWallpaperGrid,
              result: EventResultValue.success,
              loadTimeMs: loadTimeMs,
              sourceContext: 'home_wallpaper_grid_initial',
              itemCount: itemCount,
            ),
          );
        },
      );
    }

    if (subWalls.isEmpty && state.status == LoadStatus.success) {
      return RefreshIndicator(
        backgroundColor: Theme.of(context).primaryColor,
        key: refreshHomeKey,
        onRefresh: refreshList,
        child: ListView(
          children: const [
            SizedBox(height: 220),
            Center(child: Text('No wallpapers loaded. Pull to retry.')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5.0),
      child: RefreshIndicator(
        backgroundColor: Theme.of(context).primaryColor,
        key: refreshHomeKey,
        onRefresh: refreshList,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            _scrollMilestoneTracker.onScroll(
              metrics: scrollInfo.metrics,
              itemCount: subWalls.length,
              onMilestoneReached: (depth, {required int itemCount}) async {
                await analytics.track(
                  ScrollMilestoneReachedEvent(
                    surface: AnalyticsSurfaceValue.homeWallpaperGrid,
                    listName: ScrollListNameValue.wallpaperGrid,
                    depth: depth,
                    sourceContext: 'home_wallpaper_grid_scroll',
                    itemCount: itemCount,
                  ),
                );
              },
            );
            if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
              unawaited(_triggerSeeMore(hasMore: state.hasMore, currentItemCount: subWalls.length));
            }
            return false;
          },
          child: GridView.builder(
            physics: const ScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: showSkeletonTiles ? 20 : subWalls.length,
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).orientation == Orientation.portrait ? 3 : 5,
              childAspectRatio: 0.5,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
            ),
            itemBuilder: (context, index) {
              if (showSkeletonTiles) {
                return Container(
                  decoration: BoxDecoration(
                    color: context.prismModeStyleForContext() == "Dark"
                        ? Colors.white10
                        : Colors.black.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }
              final int itemIndex = index;
              if (itemIndex == subWalls.length - 1) {
                return SeeMoreButton(
                  seeMoreLoader: seeMoreLoader,
                  func: () {
                    unawaited(
                      analytics.track(
                        const SurfaceActionTappedEvent(
                          surface: AnalyticsSurfaceValue.homeWallpaperGrid,
                          action: AnalyticsActionValue.seeMoreTapped,
                          sourceContext: 'home_wallpaper_grid_see_more',
                        ),
                      ),
                    );
                    unawaited(_triggerSeeMore(hasMore: state.hasMore, currentItemCount: subWalls.length));
                  },
                );
              }
              final PrismFeedItem item = subWalls[itemIndex];
              return WallpaperTile(item: item, index: itemIndex);
            },
          ),
        ),
      ),
    );
  }
}
