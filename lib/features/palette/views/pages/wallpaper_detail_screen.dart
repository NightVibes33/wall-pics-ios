import 'dart:async';
import 'dart:math' as math;
import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/analytics/trackers/content_load_tracker.dart';
import 'package:Prism/core/platform/wallpaper_capability.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/core/utils/edge_to_edge_overlay_style.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/core/widgets/common/autoplay_video_preview.dart';
import 'package:Prism/core/widgets/common/parallax_archive_image.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/core/wallpaper/wallpaper_variants.dart';
import 'package:Prism/core/widgets/menuButton/editButton.dart';
import 'package:Prism/core/widgets/menuButton/favWallpaperButton.dart';
import 'package:Prism/core/widgets/menuButton/setWallpaperButton.dart';
import 'package:Prism/core/widgets/content_report/content_report_sheet.dart';
import 'package:Prism/core/widgets/menuButton/shareButton.dart';
import 'package:Prism/features/ads/views/widgets/download_button.dart';
import 'package:Prism/features/favourite_walls/domain/entities/favourite_wall_entity.dart';
import 'package:Prism/features/palette/domain/bloc/wallpaper_detail_bloc.dart';
import 'package:Prism/features/palette/domain/bloc/wallpaper_detail_event.dart';
import 'package:Prism/features/palette/domain/bloc/wallpaper_detail_state.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_gallery_store.dart';
import 'package:Prism/features/palette/palette.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:screenshot/screenshot.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:timeago/timeago.dart' as timeago;

@RoutePage()
class WallpaperDetailScreen extends StatefulWidget {
  const WallpaperDetailScreen({
    super.key,
    this.entity,
    this.wallId,
    this.source,
    this.wallpaperUrl,
    this.thumbnailUrl,
    this.analyticsSurface = AnalyticsSurfaceValue.wallpaperScreen,
  }) : assert(entity != null || (wallId != null && source != null), 'Either entity or wallId+source must be provided');

  final WallpaperDetailEntity? entity;
  final String? wallId;
  final WallpaperSource? source;
  final String? wallpaperUrl;
  final String? thumbnailUrl;
  final AnalyticsSurfaceValue analyticsSurface;

  @override
  State<WallpaperDetailScreen> createState() => _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends State<WallpaperDetailScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ContentLoadTracker _contentLoadTracker = ContentLoadTracker();

  static const double _sheetHPad = 24.0;
  static const double _panelSideInset = 10.0;
  static const double _panelTopRadius = 20.0;
  static const double _chromePad = 8.0;
  static const double _minInteractiveTarget = 48.0;

  late AnimationController shakeController;
  late Animation<double> _offsetAnimation;
  ScreenshotController screenshotController = ScreenshotController();
  PanelController panelController = PanelController();
  int _toastFirstTime = 0;
  List<WallpaperDetailEntity> _galleryItems = const <WallpaperDetailEntity>[];
  int _galleryIndex = 0;
  double _activeDragDx = 0;
  double _activeDragDy = 0;
  String? _parallaxCompositeIdentity;
  String? _parallaxCompositePath;

  /// Identity for the wallpaper currently shown; resets capture readiness when it changes.
  String? _wallpaperLoadIdentity;
  int _wallpaperCaptureGeneration = 0;
  bool _wallpaperReadyForCapture = false;

  String _getSourceContext(WallpaperDetailState? blocState) {
    final source = blocState is WallpaperDetailLoaded ? blocState.entity.source : widget.source;
    return '${source?.wireValue ?? 'unknown'}_wallpaper_screen';
  }

  void _trackAction(WallpaperDetailState? blocState, AnalyticsActionValue action) {
    final itemId = blocState is WallpaperDetailLoaded ? blocState.entity.id : null;
    unawaited(
      analytics.track(
        SurfaceActionTappedEvent(
          surface: widget.analyticsSurface,
          action: action,
          sourceContext: _getSourceContext(blocState),
          itemType: ItemTypeValue.wallpaper,
          itemId: itemId,
        ),
      ),
    );
  }

  void _handlePanelOpened(BuildContext context, WallpaperDetailLoaded state) {
    final bloc = context.read<WallpaperDetailBloc>();
    bloc.add(const OnPanelOpened());
    _trackAction(state, AnalyticsActionValue.panelOpened);

    if (state.panelClosed) {
      logger.d('Screenshot Starting');
      final gen = _wallpaperCaptureGeneration;
      unawaited(_captureWallpaperScreenshotWhenReady(context, bloc, gen));
    }
  }

  Future<void> _captureWallpaperScreenshotWhenReady(
    BuildContext context,
    WallpaperDetailBloc bloc,
    int captureGeneration,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (mounted && captureGeneration == _wallpaperCaptureGeneration && !_wallpaperReadyForCapture) {
      if (DateTime.now().isAfter(deadline)) return;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || captureGeneration != _wallpaperCaptureGeneration) return;

    final current = bloc.state;
    if (current is! WallpaperDetailLoaded) return;

    final shouldCapture = current.colorChanged || (_isPrismParallax(current.entity) && _parallaxCompositePath == null);
    final capture = shouldCapture
        ? screenshotController.capture(pixelRatio: 3, delay: const Duration(milliseconds: 10))
        : Future<Uint8List?>.value();

    try {
      final Uint8List? image = await capture;
      if (image != null && mounted && captureGeneration == _wallpaperCaptureGeneration) {
        bloc.add(CaptureScreenshot(imageBytes: image));
        logger.d('Screenshot Taken');
      }
    } catch (e, st) {
      logger.d('$e\n$st');
    }
  }

  String _imageIdentity(WallpaperDetailEntity entity) => '${entity.id}|${entity.fullUrl}|${entity.thumbnailUrl}';

  void _syncWallpaperIdentity(WallpaperDetailEntity entity) {
    final key = _imageIdentity(entity);
    if (_wallpaperLoadIdentity != key) {
      _wallpaperLoadIdentity = key;
      _wallpaperCaptureGeneration++;
      _wallpaperReadyForCapture = false;
      _parallaxCompositeIdentity = null;
      _parallaxCompositePath = null;
    }
  }

  void _handleParallaxCompositeReady(WallpaperDetailEntity entity, String path) {
    final identity = _imageIdentity(entity);
    final cleanPath = path.trim();
    if (!mounted || cleanPath.isEmpty || _wallpaperLoadIdentity != identity) return;
    if (_parallaxCompositeIdentity == identity && _parallaxCompositePath == cleanPath) return;
    setState(() {
      _parallaxCompositeIdentity = identity;
      _parallaxCompositePath = cleanPath;
    });
  }

  String? _parallaxCompositePathFor(WallpaperDetailEntity entity) {
    final identity = _imageIdentity(entity);
    if (_parallaxCompositeIdentity == identity && (_parallaxCompositePath?.trim().isNotEmpty ?? false)) {
      return _parallaxCompositePath;
    }
    return null;
  }

  void _hydrateGalleryContext() {
    final initialEntity = widget.entity;
    if (initialEntity == null) {
      _galleryItems = const <WallpaperDetailEntity>[];
      _galleryIndex = 0;
      return;
    }
    final snapshot = WallpaperDetailGalleryStore.snapshotFor(initialEntity);
    if (snapshot == null) {
      _galleryItems = <WallpaperDetailEntity>[initialEntity];
      _galleryIndex = 0;
      return;
    }
    _galleryItems = snapshot.items;
    _galleryIndex = snapshot.index;
  }

  void _showGalleryOffset(BuildContext context, int offset) {
    if (_galleryItems.length < 2 || offset == 0) return;
    final nextIndex = (_galleryIndex + offset) % _galleryItems.length;
    final wrappedIndex = nextIndex < 0 ? nextIndex + _galleryItems.length : nextIndex;
    final nextEntity = _galleryItems[wrappedIndex];
    setState(() {
      _galleryIndex = wrappedIndex;
      _wallpaperReadyForCapture = false;
    });
    WallpaperDetailGalleryStore.setFromEntities(items: _galleryItems, index: wrappedIndex);
    _precacheGalleryNeighbors(context, wrappedIndex);
    _contentLoadTracker.start();
    context.read<WallpaperDetailBloc>().add(LoadFromEntity(entity: nextEntity, analyticsSurface: widget.analyticsSurface));
    HapticFeedback.selectionClick();
  }

  void _precacheGalleryNeighbors(BuildContext context, int index) {
    if (_galleryItems.length < 2) return;
    for (final offset in const <int>[-2, -1, 0, 1, 2]) {
      final nextIndex = (index + offset) % _galleryItems.length;
      final wrappedIndex = nextIndex < 0 ? nextIndex + _galleryItems.length : nextIndex;
      final entity = _galleryItems[wrappedIndex];
      for (final url in <String>[entity.thumbnailUrl.trim(), entity.fullUrl.trim()]) {
        if (url.isEmpty || _isVideoUrl(url) || _isArchiveUrl(url)) continue;
        unawaited(precacheImage(CachedNetworkImageProvider(url), context).catchError((Object _) {}));
      }
    }
  }

  void _resetActiveDrag() {
    _activeDragDx = 0;
    _activeDragDy = 0;
  }

  void _scheduleWallpaperDisplayReady() {
    if (_wallpaperReadyForCapture) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _wallpaperReadyForCapture) return;
      setState(() => _wallpaperReadyForCapture = true);
    });
  }

  void _handlePanelClosed(BuildContext context, WallpaperDetailLoaded state) {
    context.read<WallpaperDetailBloc>().add(const OnPanelClosed());
    _trackAction(state, AnalyticsActionValue.panelClosed);
  }

  void _handleAccentTap(BuildContext context, WallpaperDetailLoaded state) {
    final colors = state.colors;
    final accent = state.accent;

    if (colors == null || colors.isEmpty || !colors.contains(accent)) return;

    context.read<WallpaperDetailBloc>().add(const CycleAccentColor());
    _setStatusBarIconBrightness(state.accent ?? Colors.white);
    _trackAction(state, AnalyticsActionValue.paletteCycleTapped);

    if (_toastFirstTime == 0) {
      toasts.codeSend('Long press to reset');
      _toastFirstTime = 1;
    }
  }

  void _handleAccentLongPress(BuildContext context, WallpaperDetailLoaded state) {
    context.read<WallpaperDetailBloc>().add(const ResetAccentColor());
    _trackAction(state, AnalyticsActionValue.paletteResetLongPressed);
    HapticFeedback.vibrate();
    if (!MediaQuery.disableAnimationsOf(context)) {
      shakeController.forward(from: 0.0);
    }
  }

  void _handleColorSelected(BuildContext context, WallpaperDetailLoaded state, Color color) {
    context.read<WallpaperDetailBloc>().add(SelectAccentColor(color: color));
    _setStatusBarIconBrightness(color);
  }

  void _setStatusBarIconBrightness(Color color) {
    if (color.computeLuminance() > 0.5) {
      applyEdgeToEdgeOverlayStyle(statusBarIconBrightness: Brightness.dark);
    } else {
      applyEdgeToEdgeOverlayStyle(statusBarIconBrightness: Brightness.light);
    }
  }

  @override
  void initState() {
    super.initState();
    shakeController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _offsetAnimation =
        Tween(begin: 0.0, end: 48.0).chain(CurveTween(curve: Curves.easeOutCubic)).animate(shakeController)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) shakeController.reverse();
          });
    _contentLoadTracker.start();
    _hydrateGalleryContext();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precacheGalleryNeighbors(context, _galleryIndex);
      }
    });

    final bloc = context.read<WallpaperDetailBloc>();
    if (widget.entity != null) {
      bloc.add(LoadFromEntity(entity: widget.entity!, analyticsSurface: widget.analyticsSurface));
    } else {
      bloc.add(
        LoadFromId(
          wallId: widget.wallId!,
          source: widget.source!,
          wallpaperUrl: widget.wallpaperUrl,
          thumbnailUrl: widget.thumbnailUrl,
          analyticsSurface: widget.analyticsSurface,
        ),
      );
    }
  }

  @override
  void dispose() {
    shakeController.dispose();
    super.dispose();
  }

  void _retryWallpaperLoad(BuildContext context) {
    final bloc = context.read<WallpaperDetailBloc>();
    final currentState = bloc.state;
    if (currentState is WallpaperDetailLoaded) {
      bloc.add(LoadFromEntity(entity: currentState.entity, analyticsSurface: widget.analyticsSurface));
    } else if (widget.entity != null) {
      bloc.add(LoadFromEntity(entity: widget.entity!, analyticsSurface: widget.analyticsSurface));
    } else {
      bloc.add(
        LoadFromId(
          wallId: widget.wallId!,
          source: widget.source!,
          wallpaperUrl: widget.wallpaperUrl,
          thumbnailUrl: widget.thumbnailUrl,
          analyticsSurface: widget.analyticsSurface,
        ),
      );
    }
  }

  double _topOverlayPadding(BuildContext context) {
    final inset = app_state.notchSize ?? MediaQuery.paddingOf(context).top;
    return inset + _chromePad;
  }

  String _colorHexForClipboard(Color color) {
    final argb = color.toARGB32();
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  FavouriteWallEntity _toFavouriteWall(WallpaperDetailEntity entity) {
    return entity.when(
      prism: (wallpaper) => PrismFavouriteWall(id: wallpaper.id, wallpaper: wallpaper),
      wallhaven: (wallpaper) => WallhavenFavouriteWall(id: wallpaper.id, wallpaper: wallpaper),
      pexels: (wallpaper) => PexelsFavouriteWall(id: wallpaper.id, wallpaper: wallpaper),
    );
  }

  bool _isPrismContentType(WallpaperDetailEntity entity, String contentType) {
    return entity.when(
      prism: (wallpaper) => wallpaper.aiMetadata?['catalogContentType'] == contentType,
      wallhaven: (_) => false,
      pexels: (_) => false,
    );
  }

  bool _isPrismPremiumCatalogContent(WallpaperDetailEntity entity) {
    return entity.when(
      prism: (wallpaper) {
        final raw = wallpaper.aiMetadata?['catalogIsPremium'];
        if (raw is bool) return raw;
        final value = raw?.toString().trim().toLowerCase() ?? '';
        return value == '1' || value == 'true' || value == 'yes';
      },
      wallhaven: (_) => false,
      pexels: (_) => false,
    );
  }

  bool _isPrismLivePhoto(WallpaperDetailEntity entity) {
    return _isPrismContentType(entity, PrismCatalogDataSource.liveContentType);
  }

  bool _isPrismDiyTemplate(WallpaperDetailEntity entity) {
    return _isPrismContentType(entity, PrismCatalogDataSource.diyTemplateContentType) ||
        _isPrismContentType(entity, PrismCatalogDataSource.liveDiyTemplateContentType);
  }

  bool _isPrismParallax(WallpaperDetailEntity entity) {
    return _isPrismContentType(entity, PrismCatalogDataSource.parallaxContentType);
  }

  bool _isPrismMatchingSet(WallpaperDetailEntity entity) {
    return _isPrismContentType(entity, PrismCatalogDataSource.matchingContentType) ||
        _isPrismContentType(entity, PrismCatalogDataSource.doubleContentType);
  }

  List<String> _matchingDownloadUrlsForEntity(WallpaperDetailEntity entity) {
    if (!_isPrismMatchingSet(entity)) return const <String>[];
    return _catalogPairedImageUrlsForEntity(entity);
  }

  String _matchingDownloadLabel(int index, int count) {
    if (count == 2) {
      return index == 0 ? 'Left' : 'Right';
    }
    return 'Side ${index + 1}';
  }

  String _prismMetadataValue(WallpaperDetailEntity entity, String key) {
    return entity.when(
      prism: (wallpaper) => wallpaper.aiMetadata?[key]?.toString().trim() ?? '',
      wallhaven: (_) => '',
      pexels: (_) => '',
    );
  }

  double? _prismMetadataDouble(WallpaperDetailEntity entity, String key) {
    return entity.when(
      prism: (wallpaper) {
        final raw = wallpaper.aiMetadata?[key];
        if (raw is num) return raw.toDouble();
        return double.tryParse(raw?.toString().trim() ?? '');
      },
      wallhaven: (_) => null,
      pexels: (_) => null,
    );
  }

  bool _isVideoUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.mp4') || path.endsWith('.mov');
  }

  bool _isArchiveUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.zip');
  }

  bool _isCatalogPreviewUrl(String url) {
    return PrismCatalogDataSource.isCatalogPreviewAssetUrl(url);
  }

  bool _isSafeImageUrl(String url) {
    return url.trim().isNotEmpty && !_isVideoUrl(url) && !_isArchiveUrl(url) && !_isCatalogPreviewUrl(url);
  }

  String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _catalogDisplayImageUrl(WallpaperDetailEntity entity) {
    final pairedImageUrls = _catalogPairedImageUrlsForEntity(entity).where(_isSafeImageUrl).toList(growable: false);
    if (pairedImageUrls.isNotEmpty) return pairedImageUrls.first;

    final full = entity.fullUrl.trim();
    if (_isSafeImageUrl(full)) return full;
    final originalStill = _prismMetadataValue(entity, 'catalogOriginalStillUrl');
    if (_isSafeImageUrl(originalStill)) return originalStill;
    final thumb = entity.thumbnailUrl.trim();
    if (_isSafeImageUrl(thumb)) return thumb;
    return '';
  }

  String _catalogParallaxFileUrl(WallpaperDetailEntity entity) {
    if (!_isPrismParallax(entity)) return '';
    final explicit = _prismMetadataValue(entity, 'catalogParallaxFileUrl');
    if (explicit.isNotEmpty && _isArchiveUrl(explicit)) return explicit;
    final full = entity.fullUrl.trim();
    if (_isArchiveUrl(full)) return full;
    return '';
  }

  String _catalogLiveStillUrl(WallpaperDetailEntity entity) {
    return _firstNonEmpty(
      <String>[
        _prismMetadataValue(entity, 'catalogOriginalStillUrl'),
      ].where(_isSafeImageUrl),
    );
  }

  String _catalogLiveVideoUrl(WallpaperDetailEntity entity) {
    final full = entity.fullUrl.trim();
    return _firstNonEmpty(<String>[
      _prismMetadataValue(entity, 'catalogOriginalVideoUrl'),
      _isVideoUrl(full) && !_isCatalogPreviewUrl(full) ? full : '',
      _prismMetadataValue(entity, 'catalogVideoUrl'),
    ].where((url) => url.trim().isNotEmpty && _isVideoUrl(url) && !_isCatalogPreviewUrl(url)));
  }

  List<String> _catalogPairedImageUrlsForEntity(WallpaperDetailEntity entity) {
    return entity.when(
      prism: _catalogPairedImageUrls,
      wallhaven: (_) => const <String>[],
      pexels: (_) => const <String>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<WallpaperDetailBloc, WallpaperDetailState>(
          listener: (context, state) {
            if (state is WallpaperDetailLoaded && state.colors != null && state.accent != null) {
              _setStatusBarIconBrightness(state.accent!);
            }
          },
        ),
        BlocListener<PaletteBloc, PaletteState>(
          listener: (context, paletteState) {
            if (paletteState.status == LoadStatus.success && paletteState.palette.paletteColorValues.isNotEmpty) {
              final paletteColors = paletteState.palette.paletteColorValues.map((c) => Color(c)).toList();
              context.read<WallpaperDetailBloc>().add(UpdateColorsFromPalette(colors: paletteColors));
            }
          },
        ),
      ],
      child: BlocBuilder<WallpaperDetailBloc, WallpaperDetailState>(
        builder: (context, state) {
          return switch (state) {
            WallpaperDetailInitial() || WallpaperDetailLoading() => _buildLoadingState(state),
            WallpaperDetailLoaded() => _buildLoadedState(context, state),
            WallpaperDetailError() => _buildErrorState(state),
          };
        },
      ),
    );
  }

  Widget _buildLoadingState(WallpaperDetailState state) {
    final thumbnailUrl = state is WallpaperDetailLoading ? state.thumbnailUrl : widget.thumbnailUrl;

    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: thumbnailUrl,
              fit: BoxFit.contain,
              placeholder: (ctx, _) => const ColoredBox(color: Colors.black),
              errorWidget: (ctx, _, _) => const ColoredBox(color: Colors.black),
            ),
            Center(
              child: Semantics(label: 'Loading wallpaper', child: const CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Center(
        child: Semantics(label: 'Loading wallpaper', child: const CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildErrorState(WallpaperDetailError state) {
    final scheme = Theme.of(context).colorScheme;
    final message = state.message.trim();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: 'Error',
                child: Icon(Icons.error_outline, size: 64, color: scheme.error),
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Please try again later',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: () => _retryWallpaperLoad(context), child: const Text('Try again')),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadedState(BuildContext context, WallpaperDetailLoaded state) {
    final paletteLoading = context.select<PaletteBloc, bool>((bloc) {
      final status = bloc.state.status;
      return status == LoadStatus.loading || status == LoadStatus.initial;
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: paletteLoading ? Theme.of(context).primaryColor : state.accent,
      body: SlidingUpPanel(
        onPanelOpened: () => _handlePanelOpened(context, state),
        onPanelClosed: () => _handlePanelClosed(context, state),
        backdropEnabled: true,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(_panelTopRadius),
          topRight: Radius.circular(_panelTopRadius),
        ),
        boxShadow: const [],
        minHeight: _panelMinHeight(context),
        parallaxEnabled: true,
        parallaxOffset: 0,
        color: Colors.transparent,
        maxHeight: _panelMaxHeight(context),
        controller: panelController,
        backdropOpacity: 0,
        panel: _buildInfoPanel(context, state),
        body: _buildImageBody(context, _offsetAnimation, paletteLoading, state),
      ),
    );
  }

  double _panelMinHeight(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return math.max(128.0, bottomInset + 112.0);
  }

  double _panelMaxHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height * 0.43;
  }

  double _panelBottomMargin(BuildContext context) {
    return math.max(_panelSideInset, MediaQuery.paddingOf(context).bottom + 36.0);
  }

  Widget _buildInfoPanel(BuildContext context, WallpaperDetailLoaded state) {
    final entity = state.entity;
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final size = Size(w - _panelSideInset * 2, h * 0.43);

    return Container(
      margin: EdgeInsets.fromLTRB(_panelSideInset, 0, _panelSideInset, _panelBottomMargin(context)),
      height: size.height,
      width: size.width,
      child: LiquidGlassLayer(
        settings: LiquidGlassSettings(
          thickness: 40,
          ambientStrength: 0.2,
          blur: 4,
          glassColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
        ),
        fake: defaultTargetPlatform != TargetPlatform.iOS,
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 56),
          child: SizedBox(
            height: size.height,
            width: size.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCollapseHandle(context, state),
                _buildColorBar(context, state),
                Expanded(
                  flex: 8,
                  child: SingleChildScrollView(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollStartNotification) {
                          context.read<WallpaperDetailBloc>().add(const OnPanelScrollStart());
                        } else if (notification is ScrollEndNotification) {
                          Future.delayed(const Duration(milliseconds: 200), () {
                            if (!context.mounted) return;
                            context.read<WallpaperDetailBloc>().add(const OnPanelScrollEnd());
                          });
                        }
                        return false;
                      },
                      child: _buildMetadataRow(context, entity, state),
                    ),
                  ),
                ),
                _buildActionButtons(context, state),
                const SizedBox(height: _sheetHPad),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapseHandle(BuildContext context, WallpaperDetailLoaded state) {
    final isCollapsed = state.panelCollapsed;
    return Center(
      child: Semantics(
        button: true,
        label: isCollapsed ? 'Expand wallpaper details' : 'Collapse wallpaper details',
        child: GestureDetector(
          onTap: () {
            if (state.panelScrollInProgress) return;
            _trackAction(state, AnalyticsActionValue.panelCollapseTapped);
            if (panelController.isPanelOpen) {
              panelController.close();
            } else {
              panelController.open();
            }
          },
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _minInteractiveTarget, minHeight: _minInteractiveTarget),
            child: Center(
              child: Icon(
                isCollapsed ? JamIcons.chevron_up : JamIcons.chevron_down,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorBar(BuildContext context, WallpaperDetailLoaded state) {
    final colors = state.colors;
    final thumbnailUrl = _catalogDisplayImageUrl(state.entity).trim();
    final colorCount = colors?.length ?? 0;

    // Build the default (no-filter) swatch + one swatch per palette color.
    final swatches = <Widget>[
      _buildColorSwatch(
        context: context,
        thumbnailUrl: thumbnailUrl,
        color: null,
        isSelected: !state.colorChanged,
        onTap: () {
          context.read<WallpaperDetailBloc>().add(const ResetAccentColor());
          _setStatusBarIconBrightness(state.accent ?? Colors.white);
        },
        onLongPress: null,
      ),
      ...List.generate(colorCount, (index) {
        final color = colors![index];
        final isSelected = state.colorChanged && color == state.accent;
        return _buildColorSwatch(
          context: context,
          thumbnailUrl: thumbnailUrl,
          color: color,
          isSelected: isSelected,
          onTap: color != null ? () => _handleColorSelected(context, state, color) : null,
          onLongPress: color != null
              ? () {
                  HapticFeedback.vibrate();
                  Clipboard.setData(ClipboardData(text: _colorHexForClipboard(color))).then((_) => toasts.color(color));
                }
              : null,
        );
      }),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _sheetHPad, vertical: 8),
      height: 88,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(children: swatches.map((s) => Expanded(child: s)).toList()),
      ),
    );
  }

  Widget _buildColorSwatch({
    required BuildContext context,
    required String thumbnailUrl,
    required Color? color,
    required bool isSelected,
    required VoidCallback? onTap,
    required VoidCallback? onLongPress,
  }) {
    final label = color == null ? 'Original wallpaper colors' : 'Accent color';
    final hint = color == null ? null : 'Long press to copy hex color';
    return Semantics(
      button: onTap != null,
      selected: isSelected,
      label: label,
      hint: hint,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumbnailUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                imageBuilder: (ctx, imageProvider) => Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                      colorFilter: color != null ? ColorFilter.mode(color, BlendMode.hue) : null,
                    ),
                    border: Border(bottom: BorderSide(color: color ?? Theme.of(ctx).colorScheme.secondary, width: 8)),
                  ),
                ),
                placeholder: (_, u) =>
                    Container(color: color ?? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1)),
                errorWidget: (_, u, e) =>
                    Container(color: color ?? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1)),
              )
            else
              Container(color: color ?? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1)),
            AnimatedOpacity(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
              opacity: isSelected ? 1.0 : 0.0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(JamIcons.check, size: 14, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context, WallpaperDetailEntity entity, WallpaperDetailLoaded state) {
    return entity.when(
      prism: (wallpaper) => _buildPrismMetadata(context, wallpaper, state),
      wallhaven: (_) => _buildUnsupportedSourceMetadata(context),
      pexels: (_) => _buildUnsupportedSourceMetadata(context),
    );
  }

  Widget _buildPrismMetadata(BuildContext context, PrismWallpaper wallpaper, WallpaperDetailLoaded state) {
    final pairedImageUrls = _catalogPairedImageUrls(wallpaper);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_sheetHPad, 4, _sheetHPad, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 4,
                    children: [
                      Text(
                        wallpaper.id.toUpperCase(),
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall!.copyWith(color: Theme.of(context).colorScheme.secondary),
                      ),
                      if (state.views != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Container(
                            height: 16,
                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        Text(
                          "${state.views} views",
                          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
                          ),
                        ),
                      ] else if (state.viewsLoading) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Container(
                            height: 16,
                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (wallpaper.collections?.isNotEmpty == true) ...[
                  _buildInfoRow(context, JamIcons.folder, wallpaper.collections!.take(2).join(', ')),
                  const SizedBox(height: 4),
                ],
                if (wallpaper.core.category != null) ...[
                  _buildInfoRow(context, JamIcons.unordered_list, wallpaper.core.category!),
                  const SizedBox(height: 4),
                ],
                if (pairedImageUrls.isNotEmpty) ...[
                  _buildPrismPairedPreviewRow(context, pairedImageUrls),
                  const SizedBox(height: 8),
                ],
                if (wallpaper.core.resolution != null) ...[
                  _buildInfoRow(context, JamIcons.set_square, wallpaper.core.resolution!),
                  const SizedBox(height: 4),
                ],
                if (wallpaper.core.sizeBytes != null)
                  _buildInfoRow(
                    context,
                    JamIcons.save,
                    "${(wallpaper.core.sizeBytes! / 1000000).toStringAsFixed(2)} MB",
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildPrismAuthorRow(context, wallpaper),
                if (wallpaper.core.createdAt != null) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(context, JamIcons.calendar, _formatDate(wallpaper.core.createdAt!), reversed: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _catalogPairedImageUrls(PrismWallpaper wallpaper) {
    return _metadataStringList(wallpaper.aiMetadata?['catalogPairedDownloadUrls']);
  }

  List<String> _metadataStringList(Object? rawUrls) {
    if (rawUrls is! List) return const <String>[];
    final seen = <String>{};
    return rawUrls
        .map((url) => url.toString().trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .toList(growable: false);
  }

  Widget _buildPrismPairedPreviewRow(BuildContext context, List<String> previewUrls) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(context, JamIcons.pictures, 'Paired images'),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: previewUrls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final url = previewUrls[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 58,
                  height: 88,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: scheme.secondary.withValues(alpha: 0.1)),
                  errorWidget: (_, _, _) => Container(
                    color: scheme.secondary.withValues(alpha: 0.1),
                    child: Icon(Icons.broken_image_outlined, color: scheme.secondary.withValues(alpha: 0.5)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrismAuthorRow(BuildContext context, PrismWallpaper wallpaper) {
    return const SizedBox.shrink();
  }

  Widget _buildUnsupportedSourceMetadata(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_sheetHPad, 4, _sheetHPad, 12),
      child: _buildInfoRow(context, JamIcons.database, 'Prism-only build'),
    );
  }

  Widget _buildInfoTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Theme.of(context).colorScheme.secondary),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String text, {
    bool reversed = false,
    bool showIconLast = false,
  }) {
    final iconWidget = Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7));
    final textWidget = Flexible(
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.secondary),
      ),
    );
    const spacer = SizedBox(width: 10);
    if (showIconLast || reversed) {
      return Row(mainAxisSize: MainAxisSize.min, children: [textWidget, spacer, iconWidget]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [iconWidget, spacer, textWidget]);
  }

  Widget _buildActionButtons(BuildContext context, WallpaperDetailLoaded state) {
    final entity = state.entity;
    final isLivePhoto = _isPrismLivePhoto(entity);
    final matchingDownloadUrls = _matchingDownloadUrlsForEntity(entity);
    if (matchingDownloadUrls.length >= 2) {
      return _buildMatchingActionButtons(context, state, matchingDownloadUrls);
    }

    final isParallax = _isPrismParallax(entity);
    final liveStillUrl = isLivePhoto ? _catalogLiveStillUrl(entity) : null;
    final livePhotoTimeSeconds = isLivePhoto ? _prismMetadataDouble(entity, 'catalogLivePhotoTimeSeconds') : null;
    final parallaxCompositePath = isParallax ? _parallaxCompositePathFor(entity) : null;
    final downloadUrl = isLivePhoto
        ? _catalogLiveVideoUrl(entity)
        : parallaxCompositePath ?? (isParallax ? _catalogDisplayImageUrl(entity) : entity.fullUrl);
    final setWallpaperUrl =
        !isLivePhoto && state.colorChanged && state.screenshotTaken && state.imageFile != null
            ? state.imageFile!.path
            : entity.fullUrl;
    final List<Widget> actions = <Widget>[
      _SheetActionTapScale(
        child: DownloadButton(
          colorChanged: false,
          link: downloadUrl,
          isPremiumContent: _isPrismPremiumCatalogContent(entity),
          sourceContext: _getSourceContext(state),
          isLivePhoto: isLivePhoto,
          livePhotoStillUrl: liveStillUrl,
          livePhotoTimeSeconds: livePhotoTimeSeconds,
        ),
      ),
      if (!hideSetWallpaperUi && !isLivePhoto)
        _SheetActionTapScale(
          child: SetWallpaperButton(
            colorChanged: state.colorChanged,
            url: setWallpaperUrl,
            promptNotificationPermissionOnSuccess: true,
          ),
        ),
      _SheetActionTapScale(child: FavouriteWallpaperButton(wall: _toFavouriteWall(entity), trash: false)),
      _SheetActionTapScale(
        child: ShareButton(id: entity.id, source: entity.source, url: entity.fullUrl, thumbUrl: entity.thumbnailUrl),
      ),
      if (!isLivePhoto) _SheetActionTapScale(child: EditButton(url: entity.fullUrl)),
    ];
    final String? reportWallDocId = switch (entity) {
      PrismDetailEntity(:final wallpaper) => wallpaper.remoteStoreDocumentId,
      _ => null,
    };
    if (reportWallDocId != null && reportWallDocId.isNotEmpty) {
      actions.insert(
        actions.length - 1,
        _SheetActionTapScale(
          child: GestureDetector(
            onTap: () => showContentReportSheet(
              context,
              contentType: 'wall',
              targetRemoteStoreDocId: reportWallDocId,
              subtitle: entity.id,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 4, offset: const Offset(0, 4)),
                ],
                borderRadius: BorderRadius.circular(500),
              ),
              padding: const EdgeInsets.all(17),
              child: Icon(JamIcons.flag, color: Theme.of(context).colorScheme.secondary, size: 20),
            ),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sheetHPad),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: actions),
      ),
    );
  }

  Widget _buildMatchingActionButtons(BuildContext context, WallpaperDetailLoaded state, List<String> matchingUrls) {
    final entity = state.entity;
    final sideUrls = matchingUrls;
    final actions = <Widget>[
      for (var index = 0; index < sideUrls.length; index++)
        _SheetActionTapScale(
          child: _MatchingSideDownloadButton(
            label: _matchingDownloadLabel(index, sideUrls.length),
            url: sideUrls[index],
            sourceContext: _getSourceContext(state),
            isPremiumContent: _isPrismPremiumCatalogContent(entity),
          ),
        ),
      _SheetActionTapScale(child: FavouriteWallpaperButton(wall: _toFavouriteWall(entity), trash: false)),
      _SheetActionTapScale(
        child: ShareButton(id: entity.id, source: entity.source, url: sideUrls.first, thumbUrl: entity.thumbnailUrl),
      ),
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sheetHPad),
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 18,
          runSpacing: 12,
          children: actions,
        ),
      ),
    );
  }

  Widget _buildImageBody(
    BuildContext context,
    Animation<double> offsetAnimation,
    bool paletteLoading,
    WallpaperDetailLoaded state,
  ) {
    final entity = state.entity;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final topPad = _topOverlayPadding(context);
    _syncWallpaperIdentity(entity);
    return Stack(
      children: [
        AnimatedBuilder(
          animation: offsetAnimation,
          builder: (context, child) {
            final t = reduceMotion ? 0.0 : offsetAnimation.value;
            return Semantics(
              label: 'Wallpaper',
              hint: 'Tap to cycle accent color. Long press to reset. Swipe up for details. Swipe left or right for the next wallpaper.',
              child: GestureDetector(
                onPanStart: (_) => _resetActiveDrag(),
                onPanUpdate: (details) {
                  _activeDragDx += details.delta.dx;
                  _activeDragDy += details.delta.dy;
                  if (details.delta.dy < -10 && _activeDragDy.abs() > _activeDragDx.abs()) panelController.open();
                },
                onPanEnd: (details) {
                  final velocityX = details.velocity.pixelsPerSecond.dx;
                  final horizontal = (_activeDragDx.abs() > 22 && _activeDragDx.abs() > _activeDragDy.abs() * 0.55) ||
                      velocityX.abs() > 220;
                  if (horizontal) {
                    final direction = velocityX.abs() > 280 ? (velocityX < 0 ? 1 : -1) : (_activeDragDx < 0 ? 1 : -1);
                    _showGalleryOffset(context, direction);
                  }
                  _resetActiveDrag();
                },
                onPanCancel: _resetActiveDrag,
                onLongPress: () => _handleAccentLongPress(context, state),
                onTap: () {
                  HapticFeedback.vibrate();
                  if (!paletteLoading) _handleAccentTap(context, state);
                  if (!reduceMotion) shakeController.forward(from: 0.0);
                },
                child: Screenshot(
                  controller: screenshotController,
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: t * 1.25, horizontal: t / 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(t),
                      child: _buildProgressiveWallpaperImage(
                        context: context,
                        entity: entity,
                        state: state,
                        paletteLoading: paletteLoading,
                        progressOutsideScreenshot: true,
                        onWallpaperDisplayReady: _scheduleWallpaperDisplayReady,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (!_wallpaperReadyForCapture)
          Positioned.fill(
            child: Center(
              child: Semantics(
                label: 'Loading wallpaper',
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.fromLTRB(_chromePad, topPad, _chromePad, _chromePad),
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () {
                _trackAction(state, AnalyticsActionValue.backTapped);
                Navigator.pop(context);
              },
              color: paletteLoading
                  ? Theme.of(context).colorScheme.secondary
                  : (state.accent?.computeLuminance() ?? 0) > 0.5
                  ? Colors.black
                  : Colors.white,
              icon: const Icon(JamIcons.chevron_left),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(_chromePad, topPad, _chromePad, _chromePad),
            child: IconButton(
              tooltip: 'Clock preview',
              onPressed: () {
                _trackAction(state, AnalyticsActionValue.clockOverlayOpened);
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) {
                      animation = Tween(begin: 0.0, end: 1.0).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: ClockOverlay(
                          colorChanged: state.colorChanged,
                          accent: state.accent,
                          link: _catalogDisplayImageUrl(entity),
                          file: false,
                        ),
                      );
                    },
                    fullscreenDialog: true,
                    opaque: false,
                  ),
                );
              },
              color: paletteLoading
                  ? Theme.of(context).colorScheme.secondary
                  : (state.accent?.computeLuminance() ?? 0) > 0.5
                  ? Colors.black
                  : Colors.white,
              icon: const Icon(JamIcons.clock),
            ),
          ),
        ),
      ],
    );
  }

  /// Thumbnail first, loader while full resolution downloads, then full image on top (Wallhaven/Pexels).
  ///
  /// When [progressOutsideScreenshot] is true, download progress is not painted inside this subtree
  /// (so [Screenshot] cannot capture spinners); use [onWallpaperDisplayReady] when the full bitmap
  /// is shown or an error/empty state is finalized.
  Widget _buildProgressiveWallpaperImage({
    required BuildContext context,
    required WallpaperDetailEntity entity,
    required WallpaperDetailLoaded state,
    required bool paletteLoading,
    bool progressOutsideScreenshot = false,
    VoidCallback? onWallpaperDisplayReady,
  }) {
    final bool previewOnly = _isPrismDiyTemplate(entity);
    final bool isLivePhoto = _isPrismLivePhoto(entity);
    final String thumb = entity.thumbnailUrl.trim();
    final String entityFull = entity.fullUrl.trim();
    final String full = isLivePhoto
        ? _catalogLiveVideoUrl(entity)
        : previewOnly && !_isVideoUrl(entityFull)
            ? _catalogDisplayImageUrl(entity)
            : entityFull;
    final bool useProgressive = thumb.isNotEmpty && full.isNotEmpty && full != thumb && !_isVideoUrl(full) && !_isArchiveUrl(full);
    final pairedImageUrls = _catalogPairedImageUrlsForEntity(entity);
    final parallaxArchiveUrl = _catalogParallaxFileUrl(entity);

    Widget imageLayer;
    if (parallaxArchiveUrl.isNotEmpty) {
      imageLayer = ParallaxArchiveImage(
        archiveUrl: parallaxArchiveUrl,
        fallbackUrl: _catalogDisplayImageUrl(entity),
        fit: BoxFit.contain,
        onReady: onWallpaperDisplayReady,
        onCompositeReady: (path) => _handleParallaxCompositeReady(entity, path),
      );
    } else if (pairedImageUrls.length < 2 && full.isNotEmpty && _isVideoUrl(full)) {
      imageLayer = AutoplayVideoPreview(
        videoUrl: full,
        posterUrl: isLivePhoto ? _catalogLiveStillUrl(entity) : null,
        fit: BoxFit.contain,
        playbackSpeed: 1.0,
        onReady: onWallpaperDisplayReady,
      );
    } else if (pairedImageUrls.length >= 2) {
      Widget pairedSide(String url) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          imageBuilder: (context, imageProvider) {
            onWallpaperDisplayReady?.call();
            return SizedBox.expand(child: Image(image: imageProvider, fit: BoxFit.contain));
          },
          placeholder: (context, url) => Container(color: Theme.of(context).primaryColor),
          errorWidget: (context, url, error) {
            onWallpaperDisplayReady?.call();
            return Center(
              child: Icon(JamIcons.close_circle_f, color: _wallpaperErrorIconColor(context, paletteLoading, state)),
            );
          },
        );
      }

      final rows = <Widget>[];
      for (var index = 0; index < pairedImageUrls.length; index += 2) {
        rows.add(
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: pairedSide(pairedImageUrls[index])),
                const SizedBox(width: 3, child: ColoredBox(color: Colors.black)),
                if (index + 1 < pairedImageUrls.length)
                  Expanded(child: pairedSide(pairedImageUrls[index + 1]))
                else
                  const Spacer(),
              ],
            ),
          ),
        );
        if (index + 2 < pairedImageUrls.length) {
          rows.add(const SizedBox(height: 3, child: ColoredBox(color: Colors.black)));
        }
      }

      imageLayer = Column(children: rows);
    } else if (useProgressive) {
      imageLayer = Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            imageBuilder: (context, imageProvider) {
              onWallpaperDisplayReady?.call();
              return SizedBox.expand(child: Image(image: imageProvider, fit: BoxFit.contain));
            },
            placeholder: (context, url) => Container(color: Theme.of(context).primaryColor),
            errorWidget: (context, url, error) {
              onWallpaperDisplayReady?.call();
              return Center(
                child: Icon(JamIcons.close_circle_f, color: _wallpaperErrorIconColor(context, paletteLoading, state)),
              );
            },
          ),
          CachedNetworkImage(
            imageUrl: full,
            fit: BoxFit.contain,
            fadeInDuration: const Duration(milliseconds: 280),
            fadeOutDuration: Duration.zero,
            imageBuilder: (context, imageProvider) {
              onWallpaperDisplayReady?.call();
              return SizedBox.expand(
                child: Image(image: imageProvider, fit: BoxFit.contain),
              );
            },
            progressIndicatorBuilder: progressOutsideScreenshot
                ? (context, url, downloadProgress) => const SizedBox.shrink()
                : (context, url, downloadProgress) => Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                      value: downloadProgress.progress,
                    ),
                  ),
            errorWidget: (context, url, error) {
              onWallpaperDisplayReady?.call();
              return const SizedBox.shrink();
            },
          ),
        ],
      );
    } else {
      final String url = full.isNotEmpty ? full : thumb;
      if (url.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onWallpaperDisplayReady?.call();
        });
        imageLayer = Center(
          child: Icon(JamIcons.close_circle_f, color: _wallpaperErrorIconColor(context, paletteLoading, state)),
        );
      } else {
        imageLayer = CachedNetworkImage(
          imageUrl: url,
          imageBuilder: (context, imageProvider) {
            onWallpaperDisplayReady?.call();
            return SizedBox.expand(
              child: Image(image: imageProvider, fit: BoxFit.contain),
            );
          },
          progressIndicatorBuilder: progressOutsideScreenshot
              ? (context, url, downloadProgress) => const SizedBox.shrink()
              : (context, url, downloadProgress) => Stack(
                  fit: StackFit.expand,
                  children: [
                    const SizedBox.expand(),
                    Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                        value: downloadProgress.progress,
                      ),
                    ),
                  ],
                ),
          errorWidget: (context, url, error) {
            onWallpaperDisplayReady?.call();
            return Center(
              child: Icon(JamIcons.close_circle_f, color: _wallpaperErrorIconColor(context, paletteLoading, state)),
            );
          },
        );
      }
    }

    if (state.colorChanged && state.accent != null) {
      imageLayer = ColorFiltered(colorFilter: ColorFilter.mode(state.accent!, BlendMode.hue), child: imageLayer);
    }

    return ColoredBox(color: Colors.black, child: SizedBox.expand(child: imageLayer));
  }

  Color _wallpaperErrorIconColor(BuildContext context, bool paletteLoading, WallpaperDetailLoaded state) {
    return paletteLoading
        ? Theme.of(context).colorScheme.secondary
        : (state.accent?.computeLuminance() ?? 0) > 0.5
        ? Colors.black
        : Colors.white;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inDays < 7) return timeago.format(local);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[local.month - 1];
    if (local.year == DateTime.now().year) return '${local.day} $month';
    return '${local.day} $month ${local.year}';
  }

  String sourceDisplayName(WallpaperSource source) => switch (source) {
    WallpaperSource.prism => 'Prism',
    WallpaperSource.downloaded => 'Downloaded',
    WallpaperSource.wallhaven || WallpaperSource.pexels || WallpaperSource.unknown => 'Unsupported',
  };
}

/// Press feedback for the wallpaper sheet action row: scale only (no layout animation).
/// Skips motion when [MediaQuery.disableAnimations] is true (e.g. reduce motion).
class _SheetActionTapScale extends StatefulWidget {
  const _SheetActionTapScale({required this.child});

  final Widget child;

  @override
  State<_SheetActionTapScale> createState() => _SheetActionTapScaleState();
}

class _MatchingSideDownloadButton extends StatelessWidget {
  const _MatchingSideDownloadButton({
    required this.label,
    required this.url,
    required this.sourceContext,
    required this.isPremiumContent,
  });

  final String label;
  final String url;
  final String sourceContext;
  final bool isPremiumContent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Download $label matching wallpaper',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DownloadButton(colorChanged: false, link: url, isPremiumContent: isPremiumContent, sourceContext: sourceContext),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontFamily: 'Satoshi',
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetActionTapScaleState extends State<_SheetActionTapScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 85),
    );
    _scale = Tween<double>(
      begin: 1,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (pressed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          final s = reduceMotion ? 1.0 : _scale.value;
          return Transform.scale(scale: s, filterQuality: FilterQuality.low, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
