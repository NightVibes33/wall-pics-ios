import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/platform/pigeon/prism_media_api.g.dart';
import 'package:Prism/core/platform/wallpaper_capability.dart';
import 'package:Prism/core/platform/wallpaper_service.dart';
import 'package:Prism/core/purchases/download_access_service.dart';
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/core/widgets/menuButton/setWallpaperButton.dart';
import 'package:Prism/features/palette/views/pages/custom_filters.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imagelib;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photofilters/filters/filters.dart';
import 'package:photofilters/filters/preset_filters.dart';

@RoutePage()
class WallpaperFilterScreen extends StatefulWidget {
  const WallpaperFilterScreen({super.key, this.image, this.finalImage, this.filename, this.finalFilename});

  final imagelib.Image? image;
  final imagelib.Image? finalImage;
  final String? filename;
  final String? finalFilename;

  @override
  State<StatefulWidget> createState() => _WallpaperFilterScreenState();
}

class _WallpaperFilterScreenState extends State<WallpaperFilterScreen> {
  String? filename;
  String? finalFilename;
  final Map<String, Uint8List> _thumbnailFilterCache = <String, Uint8List>{};
  final Map<String, Uint8List> _fullFilterCache = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _thumbnailFilterFutures = <String, Future<Uint8List>>{};
  final Map<String, Future<Uint8List>> _fullFilterFutures = <String, Future<Uint8List>>{};
  Filter? _filter;
  imagelib.Image? image;
  imagelib.Image? finalImage;
  late bool loading;
  late bool isLoading;
  List<Filter> selectedFilters = [
    NoFilter(),
    AddictiveBlueFilter(),
    AddictiveRedFilter(),
    AdenFilter(),
    AmaroFilter(),
    AshbyFilter(),
    BlurFilter(),
    BlurMaxFilter(),
    BrannanFilter(),
    BrooklynFilter(),
    CharmesFilter(),
    ClarendonFilter(),
    CremaFilter(),
    DogpatchFilter(),
    EarlybirdFilter(),
    EdgeDetectionFilter(),
    EmbossFilter(),
    F1977Filter(),
    GinghamFilter(),
    GinzaFilter(),
    HefeFilter(),
    HelenaFilter(),
    HighPassFilter(),
    HudsonFilter(),
    InkwellFilter(),
    InvertFilter(),
    JunoFilter(),
    KelvinFilter(),
    LarkFilter(),
    LoFiFilter(),
    LowPassFilter(),
    LudwigFilter(),
    MavenFilter(),
    MayfairFilter(),
    MeanFilter(),
    MoonFilter(),
    NashvilleFilter(),
    PerpetuaFilter(),
    ReyesFilter(),
    RiseFilter(),
    SharpenFilter(),
    SierraFilter(),
    SkylineFilter(),
    SlumberFilter(),
    StinsonFilter(),
    SutroFilter(),
    ToasterFilter(),
    ValenciaFilter(),
    VesperFilter(),
    WaldenFilter(),
    WillowFilter(),
    XProIIFilter(),
  ];

  @override
  void initState() {
    super.initState();
    loading = false;
    isLoading = false;
    _filter = selectedFilters[0];
    image = widget.image;
    finalImage = widget.finalImage;
    filename = widget.filename;
    finalFilename = widget.finalFilename;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _setBothWallPaper(String url) async {
    bool? result;
    try {
      result = await WallpaperService.setWallpaperFromSource(url, WallpaperTarget.both);
      if (result) {
        logger.d("Success");
        analytics.track(
          const SetWallEvent(wallpaperTarget: WallpaperTargetValue.both, result: BinaryResultValue.success),
        );
        toasts.codeSend("Wallpaper set successfully!");
      } else {
        logger.d("Failed");
        toasts.error("Something went wrong!");
      }
    } catch (e) {
      analytics.track(
        const SetWallEvent(wallpaperTarget: WallpaperTargetValue.both, result: BinaryResultValue.failure),
      );
      logger.d(e.toString());
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _setLockWallPaper(String url) async {
    bool? result;
    try {
      result = await WallpaperService.setWallpaperFromSource(url, WallpaperTarget.lock);
      if (result) {
        logger.d("Success");
        analytics.track(
          const SetWallEvent(wallpaperTarget: WallpaperTargetValue.lock, result: BinaryResultValue.success),
        );
        toasts.codeSend("Wallpaper set successfully!");
      } else {
        logger.d("Failed");
        toasts.error("Something went wrong!");
      }
    } catch (e) {
      logger.d(e.toString());
      analytics.track(
        const SetWallEvent(wallpaperTarget: WallpaperTargetValue.lock, result: BinaryResultValue.failure),
      );
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _setHomeWallPaper(String url) async {
    bool? result;
    try {
      result = await WallpaperService.setWallpaperFromSource(url, WallpaperTarget.home);
      if (result) {
        logger.d("Success");
        analytics.track(
          const SetWallEvent(wallpaperTarget: WallpaperTargetValue.home, result: BinaryResultValue.success),
        );
        toasts.codeSend("Wallpaper set successfully!");
      } else {
        logger.d("Failed");
        toasts.error("Something went wrong!");
      }
    } catch (e) {
      logger.d(e.toString());
      analytics.track(
        const SetWallEvent(wallpaperTarget: WallpaperTargetValue.home, result: BinaryResultValue.failure),
      );
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _runFilterAction(Future<void> Function() action, {required String sourceTag}) async {
    logger.d('Running wallpaper filter action.', fields: <String, Object?>{'sourceTag': sourceTag});
    await action();
  }

  Future<void> _handleDownloadAction() async {
    if (isLoading || loading) {
      return;
    }
    final canDownload = await DownloadAccessService.instance.ensureCanDownload(
      context,
      contentId: widget.finalFilename ?? widget.filename ?? 'filtered-wallpaper',
      sourceContext: 'wallpaper_filter_download',
    );
    if (!canDownload) {
      return;
    }
    toasts.codeSend("Processing Wallpaper");
    final imageFile = await saveFilteredImage();
    if (!mounted) {
      return;
    }
    setState(() {
      isLoading = true;
    });
    final request = SaveMediaRequest(link: imageFile.path, isLocalFile: true, kind: SaveMediaKind.wallpaper);
    try {
      final result = await PrismMediaHostApi().saveMedia(request);
      if (result.success) {
        analytics.track(DownloadWallpaperEvent(link: imageFile.path));
        toasts.codeSend("Wall Saved in Pictures!");
      } else {
        toasts.error("Couldn't save wallpaper. Please retry!");
      }
    } on PlatformException catch (e) {
      if (e.code == 'channel-error') {
        logger.w('saveMedia channel unavailable (native side not registered)', error: e);
      } else {
        logger.e('saveMedia failed', error: e);
      }
      toasts.error("Couldn't save wallpaper. Please retry!");
    } catch (e) {
      logger.e('Unexpected saveMedia failure', error: e);
      toasts.error("Something went wrong!");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSetAction() async {
    if (loading) {
      return;
    }
    final canDownload = await DownloadAccessService.instance.ensureCanDownload(
      context,
      contentId: widget.finalFilename ?? widget.filename ?? 'filtered-wallpaper',
      sourceContext: 'wallpaper_filter_download',
    );
    if (!canDownload) {
      return;
    }
    toasts.codeSend("Processing Wallpaper");
    final imageFile = await saveFilteredImage();
    if (!mounted) {
      return;
    }
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) => SetOptionsPanel(
        onTap1: () {
          HapticFeedback.vibrate();
          Navigator.of(context).pop();
          _setHomeWallPaper(imageFile.path);
        },
        onTap2: () {
          HapticFeedback.vibrate();
          Navigator.of(context).pop();
          _setLockWallPaper(imageFile.path);
        },
        onTap3: () {
          HapticFeedback.vibrate();
          Navigator.of(context).pop();
          _setBothWallPaper(imageFile.path);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Edit Wallpaper", style: Theme.of(context).textTheme.displaySmall),
        leading: IconButton(
          icon: const Icon(JamIcons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        backgroundColor: Theme.of(context).primaryColor,
        actions: <Widget>[
          if (loading)
            Container()
          else if (isLoading)
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Theme.of(context).colorScheme.error),
              ),
            )
          else
            IconButton(
              icon: const Icon(JamIcons.download),
              onPressed: () =>
                  unawaited(_runFilterAction(_handleDownloadAction, sourceTag: 'filter.download')),
            ),
          if (!hideSetWallpaperUi)
            if (loading)
              Container()
            else
              IconButton(
                icon: const Icon(JamIcons.check),
                onPressed: () => unawaited(_runFilterAction(_handleSetAction, sourceTag: 'filter.set')),
              ),
        ],
      ),
      backgroundColor: Theme.of(context).primaryColor,
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: loading
            ? Center(child: Loader())
            : Column(
                children: [
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _buildFilteredImage(_filter, finalImage, finalFilename),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    flex: 2,
                    child: ColoredBox(
                      color: Theme.of(context).primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedFilters.length,
                        itemBuilder: (BuildContext context, int index) {
                          return GestureDetector(
                            onTap: () => setState(() {
                              _filter = selectedFilters[index];
                            }),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      _buildFilterThumbnail(selectedFilters[index], image, filename),
                                      if (_filter == selectedFilters[index])
                                        Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(500),
                                            color: Colors.white,
                                          ),
                                          child: const Icon(JamIcons.check, color: Colors.black),
                                        )
                                      else
                                        Container(),
                                    ],
                                  ),
                                  const SizedBox(height: 10.0),
                                  Text(
                                    selectedFilters[index].name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.secondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFilterThumbnail(Filter filter, imagelib.Image? image, String? filename) {
    if (image == null) {
      return _thumbnailShell(Center(child: Loader()));
    }
    final cacheKey = _filterCacheKey('thumb', filter, image, filename);
    final cached = _thumbnailFilterCache[cacheKey];
    if (cached != null) {
      return _thumbnailShell(Image(image: MemoryImage(cached), fit: BoxFit.cover));
    }
    return FutureBuilder<Uint8List>(
      future: _thumbnailFilterFutures.putIfAbsent(
        cacheKey,
        () => _computeFilteredBytes(filter: filter, image: image, filename: filename).then((bytes) {
          _thumbnailFilterCache[cacheKey] = bytes;
          return bytes;
        }),
      ),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _thumbnailShell(Center(child: Loader()));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _thumbnailShell(const Center(child: Icon(Icons.error_outline)));
        }
        final bytes = snapshot.data!;
        _thumbnailFilterCache[cacheKey] = bytes;
        return _thumbnailShell(Image(image: MemoryImage(bytes), fit: BoxFit.cover));
      },
    );
  }

  Widget _thumbnailShell(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 90.0,
        height: MediaQuery.of(context).size.height * 0.15,
        color: Theme.of(context).primaryColor,
        child: child,
      ),
    );
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();

    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    final targetName = finalFilename?.trim().isNotEmpty == true ? finalFilename!.trim() : 'wallpaper.jpg';
    return File('$path/filtered_${_safeFilePart(_filter?.name ?? "_")}_${_safeFilePart(targetName)}');
  }

  Future<File> saveFilteredImage() async {
    final imageFile = await _localFile;
    final selectedFilter = _filter;
    final image = finalImage;
    if (image == null) {
      throw StateError('No full-size wallpaper image available for filtering.');
    }
    final Uint8List finalFilterImageBytes = await _fullFilterBytes(selectedFilter, image, finalFilename);
    await imageFile.writeAsBytes(finalFilterImageBytes, flush: true);
    return imageFile;
  }

  Widget _buildFilteredImage(Filter? filter, imagelib.Image? image, String? filename) {
    if (image == null) {
      return Center(child: Loader());
    }
    final cacheKey = _filterCacheKey('full', filter, image, filename);
    final cached = _fullFilterCache[cacheKey];
    if (cached != null) {
      return _buildFilteredPhoto(cached);
    }
    return FutureBuilder<Uint8List>(
      future: _fullFilterFutures.putIfAbsent(
        cacheKey,
        () => _computeFilteredBytes(filter: filter, image: image, filename: filename).then((bytes) {
          _fullFilterCache[cacheKey] = bytes;
          return bytes;
        }),
      ),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: Loader());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final bytes = snapshot.data!;
        _fullFilterCache[cacheKey] = bytes;
        return _buildFilteredPhoto(bytes);
      },
    );
  }

  Widget _buildFilteredPhoto(Uint8List bytes) {
    return PhotoView(
      imageProvider: MemoryImage(bytes),
      backgroundDecoration: BoxDecoration(color: Theme.of(context).primaryColor),
    );
  }

  Future<Uint8List> _fullFilterBytes(Filter? filter, imagelib.Image image, String? filename) {
    final cacheKey = _filterCacheKey('full', filter, image, filename);
    final cached = _fullFilterCache[cacheKey];
    if (cached != null) {
      return Future<Uint8List>.value(cached);
    }
    return _fullFilterFutures.putIfAbsent(
      cacheKey,
      () => _computeFilteredBytes(filter: filter, image: image, filename: filename).then((bytes) {
        _fullFilterCache[cacheKey] = bytes;
        return bytes;
      }),
    );
  }

  Future<Uint8List> _computeFilteredBytes({required Filter? filter, required imagelib.Image image, required String? filename}) {
    return compute(_applyFilter, <String, dynamic>{'filter': filter, 'image': image, 'filename': filename});
  }

  String _filterCacheKey(String scope, Filter? filter, imagelib.Image? image, String? filename) {
    return <String>[
      scope,
      filter?.name ?? '_',
      '${image?.width ?? 0}x${image?.height ?? 0}',
      filename ?? '',
    ].join('|');
  }

  String _safeFilePart(String value) {
    return value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }
}

///The global applyfilter function
Uint8List _applyFilter(Map<String, dynamic> params) {
  final Filter? filter = params['filter'] as Filter?;
  final imagelib.Image? image = params['image'] as imagelib.Image?;
  final String filename = params['filename']?.toString() ?? 'filtered.jpg';
  if (image == null) {
    throw StateError('No image supplied for filtering.');
  }
  final Uint8List bytes = Uint8List.fromList(image.getBytes());
  filter?.apply(bytes, image.width, image.height);
  final imagelib.Image filteredImage = imagelib.Image.fromBytes(image.width, image.height, bytes);
  final List<int> encoded = imagelib.encodeNamedImage(filteredImage, filename) ?? imagelib.encodeJpg(filteredImage, quality: 100);
  return Uint8List.fromList(encoded);
}
