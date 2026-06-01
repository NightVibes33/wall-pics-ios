import 'dart:async';
import 'dart:io';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/platform/pigeon/prism_media_api.g.dart';
import 'package:Prism/core/platform/wallpaper_capability.dart';
import 'package:Prism/core/platform/wallpaper_service.dart';
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/core/widgets/menuButton/setWallpaperButton.dart';
import 'package:Prism/features/palette/views/pages/custom_filters.dart';
import 'package:Prism/features/theme_mode/views/theme_mode_bloc_utils.dart';
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
  Map<String, List<int>?> cachedFilters = {};
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
    final String filterName = filter.name;
    if (cachedFilters[filterName] == null) {
      return FutureBuilder<List<int>>(
        future: compute(_applyFilter, <String, dynamic>{"filter": filter, "image": image, "filename": filename}),
        builder: (BuildContext context, AsyncSnapshot<List<int>> snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.none:
            case ConnectionState.active:
            case ConnectionState.waiting:
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 90.0,
                  height: MediaQuery.of(context).size.height * 0.15,
                  color: Theme.of(context).primaryColor,
                  child: Center(child: Loader()),
                ),
              );
            case ConnectionState.done:
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              cachedFilters[filterName] = snapshot.data;
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 90.0,
                  height: MediaQuery.of(context).size.height * 0.15,
                  color: Theme.of(context).primaryColor,
                  child: Image(image: MemoryImage((snapshot.data as Uint8List?)!), fit: BoxFit.cover),
                ),
              );
          }
        },
      );
    } else {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 90.0,
          height: MediaQuery.of(context).size.height * 0.15,
          color: Theme.of(context).primaryColor,
          child: Image(image: MemoryImage(cachedFilters[filterName]! as Uint8List), fit: BoxFit.cover),
        ),
      );
    }
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();

    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/filtered_${_filter?.name ?? "_"}_$finalFilename');
  }

  Future<File> saveFilteredImage() async {
    final imageFile = await _localFile;
    final List<int> finalFilterImageBytes = await compute(_applyFilter, <String, dynamic>{
      "filter": _filter,
      "image": finalImage,
      "filename": finalFilename,
    });
    await imageFile.writeAsBytes(finalFilterImageBytes);
    return imageFile;
  }

  Widget _buildFilteredImage(Filter? filter, imagelib.Image? image, String? filename) {
    return FutureBuilder<List<int>>(
      future: compute(_applyFilter, <String, dynamic>{"filter": filter, "image": image, "filename": filename}),
      builder: (BuildContext context, AsyncSnapshot<List<int>> snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
            return cachedFilters[filter?.name ?? "_"] == null
                ? Center(child: Loader())
                : Stack(
                    children: [
                      PhotoView(
                        imageProvider: MemoryImage((cachedFilters[filter?.name ?? "_"] as Uint8List?)!),
                        backgroundDecoration: BoxDecoration(color: Theme.of(context).primaryColor),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 25,
                              width: 25,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  context.prismModeStyleForContext() == "Dark" && context.prismIsAmoledDark()
                                      ? Theme.of(context).colorScheme.error == Colors.black
                                            ? Theme.of(context).colorScheme.secondary
                                            : Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            Icon(Icons.high_quality_rounded, color: Theme.of(context).colorScheme.secondary),
                          ],
                        ),
                      ),
                    ],
                  );
          case ConnectionState.active:
          case ConnectionState.waiting:
            return cachedFilters[filter?.name ?? "_"] == null
                ? Center(child: Loader())
                : Stack(
                    children: [
                      PhotoView(
                        imageProvider: MemoryImage((cachedFilters[filter?.name ?? "_"] as Uint8List?)!),
                        backgroundDecoration: BoxDecoration(color: Theme.of(context).primaryColor),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 25,
                              width: 25,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  context.prismModeStyleForContext() == "Dark" && context.prismIsAmoledDark()
                                      ? Theme.of(context).colorScheme.error == Colors.black
                                            ? Theme.of(context).colorScheme.secondary
                                            : Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            Icon(Icons.high_quality_rounded, color: Theme.of(context).colorScheme.secondary),
                          ],
                        ),
                      ),
                    ],
                  );
          case ConnectionState.done:
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            cachedFilters[filter?.name ?? "_"] = snapshot.data;
            return PhotoView(
              imageProvider: MemoryImage((snapshot.data as Uint8List?)!),
              backgroundDecoration: BoxDecoration(color: Theme.of(context).primaryColor),
            );
        }
      },
    );
  }
}

///The global applyfilter function
List<int> _applyFilter(Map<String, dynamic> params) {
  final Filter? filter = params["filter"] as Filter?;
  final imagelib.Image image = params["image"] as imagelib.Image;
  final String filename = params["filename"] as String;
  List<int> bytes = image.getBytes();
  if (filter != null) {
    filter.apply(bytes as Uint8List, image.width, image.height);
  }
  final imagelib.Image image0 = imagelib.Image.fromBytes(image.width, image.height, bytes);

  return bytes = imagelib.encodeNamedImage(image0, filename)!;
}
