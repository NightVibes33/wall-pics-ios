import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:Prism/features/prism_catalog/data/prism_seed_media_store.dart';
import 'package:Prism/features/prism_catalog/views/prism_seed_media_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

class ParallaxArchiveFrame {
  const ParallaxArchiveFrame({required this.imagePath, required this.width, required this.height});

  final String imagePath;
  final int width;
  final int height;
}

class ParallaxArchiveCache {
  ParallaxArchiveCache._();

  static const int _minimumRenderLongSide = 3840;

  static final Map<String, Future<ParallaxArchiveFrame?>> _inFlight = <String, Future<ParallaxArchiveFrame?>>{};

  static Future<ParallaxArchiveFrame?> resolve(String archiveUrl) {
    final normalizedUrl = archiveUrl.trim();
    if (normalizedUrl.isEmpty) return Future<ParallaxArchiveFrame?>.value();
    return _inFlight.putIfAbsent(normalizedUrl, () async {
      try {
        final key = base64Url.encode(utf8.encode(normalizedUrl)).replaceAll('=', '');
        final tempDir = await getTemporaryDirectory();
        final cacheDir = Directory('${tempDir.path}/prism_parallax_archive/$key');
        final output = File('${cacheDir.path}/composite.png');
        if (await output.exists()) {
          final size = await _readImageSize(output);
          return ParallaxArchiveFrame(imagePath: output.path, width: size.width, height: size.height);
        }

        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
        await cacheDir.create(recursive: true);

        final archive = await PrismSeedMediaStore.instance.fileForUrl(normalizedUrl) ??
            await DefaultCacheManager().getSingleFile(normalizedUrl).timeout(const Duration(seconds: 45));
        await ZipFile.extractToDirectory(zipFile: archive, destinationDir: cacheDir);
        return _renderArchive(cacheDir: cacheDir, output: output);
      } catch (_) {
        return null;
      } finally {
        _inFlight.remove(normalizedUrl);
      }
    });
  }

  static Future<ParallaxArchiveFrame?> _renderArchive({
    required Directory cacheDir,
    required File output,
  }) async {
    final config = await _loadConfig(File('${cacheDir.path}/config.json'));
    final layerConfigs = (config['layers'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((layer) => Map<String, Object?>.from(layer))
        .toList(growable: false)
      ..sort((a, b) => _int(a['index']).compareTo(_int(b['index'])));

    final files = <File>[];
    for (final layer in layerConfigs) {
      final file = _findLayerFile(cacheDir, layer['filename']?.toString() ?? '');
      if (file != null) files.add(file);
    }
    if (files.isEmpty) {
      files.addAll(cacheDir.listSync().whereType<File>().where(_isSupportedImageFile));
    }
    if (files.isEmpty) return null;

    final decoded = <ui.Image>[];
    try {
      for (final file in files) {
        decoded.add(await _decodeImage(file));
      }

      final resolution = config['resolution'] is Map ? Map<String, Object?>.from(config['resolution'] as Map) : const <String, Object?>{};
      final sourceWidth = _int(resolution['width'], fallback: decoded.first.width);
      final sourceHeight = _int(resolution['height'], fallback: decoded.first.height);
      final targetSize = _highResolutionSize(width: sourceWidth, height: sourceHeight);
      final width = targetSize.width;
      final height = targetSize.height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = _backgroundColor(config['backgroundColor']));
      final target = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final paint = Paint()..filterQuality = FilterQuality.high;
      for (final image in decoded) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          target,
          paint,
        );
      }

      final picture = recorder.endRecording();
      final composite = await picture.toImage(width, height);
      final png = await composite.toByteData(format: ui.ImageByteFormat.png);
      composite.dispose();
      if (png == null) return null;
      await output.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return ParallaxArchiveFrame(imagePath: output.path, width: width, height: height);
    } finally {
      for (final image in decoded) {
        image.dispose();
      }
    }
  }

  static Future<Map<String, Object?>> _loadConfig(File file) async {
    if (!await file.exists()) return const <String, Object?>{};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? Map<String, Object?>.from(decoded) : const <String, Object?>{};
  }

  static File? _findLayerFile(Directory directory, String filename) {
    final cleanName = filename.trim();
    if (cleanName.isEmpty) return null;
    final direct = File('${directory.path}/$cleanName');
    if (direct.existsSync()) return direct;
    for (final extension in const <String>['jpg', 'jpeg', 'png', 'webp']) {
      final withExtension = File('${directory.path}/$cleanName.$extension');
      if (withExtension.existsSync()) return withExtension;
    }
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      if (stem == cleanName && _isSupportedImageFile(file)) return file;
    }
    return null;
  }

  static bool _isSupportedImageFile(File file) {
    final path = file.path.toLowerCase();
    return path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.webp');
  }

  static Future<ui.Image> _decodeImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<({int width, int height})> _readImageSize(File file) async {
    final image = await _decodeImage(file);
    final size = (width: image.width, height: image.height);
    image.dispose();
    return size;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static ({int width, int height}) _highResolutionSize({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      return (width: 2160, height: 3840);
    }
    final longSide = math.max(width, height);
    if (longSide >= _minimumRenderLongSide) {
      return (width: width, height: height);
    }
    final scale = _minimumRenderLongSide / longSide;
    return (
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  static Color _backgroundColor(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return Colors.black;
    final hex = value.startsWith('#') ? value.substring(1) : value;
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? Colors.black : Color(parsed);
  }
}

class ParallaxArchiveImage extends StatefulWidget {
  const ParallaxArchiveImage({
    required this.archiveUrl,
    this.fallbackUrl,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.onReady,
    this.onCompositeReady,
    super.key,
  });

  final String archiveUrl;
  final String? fallbackUrl;
  final BoxFit fit;
  final Alignment alignment;
  final VoidCallback? onReady;
  final ValueChanged<String>? onCompositeReady;

  @override
  State<ParallaxArchiveImage> createState() => _ParallaxArchiveImageState();
}

class _ParallaxArchiveImageState extends State<ParallaxArchiveImage> {
  Future<ParallaxArchiveFrame?>? _future;
  String? _notifiedPath;
  bool _notifiedFallback = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ParallaxArchiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.archiveUrl != widget.archiveUrl) {
      _notifiedPath = null;
      _notifiedFallback = false;
      _load();
    }
  }

  void _load() {
    _future = ParallaxArchiveCache.resolve(widget.archiveUrl);
  }

  void _notifyReady({String? path}) {
    if (path != null && path == _notifiedPath) return;
    if (path == null && _notifiedFallback) return;
    if (path != null) {
      _notifiedPath = path;
    } else {
      _notifiedFallback = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (path != null) widget.onCompositeReady?.call(path);
      widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ParallaxArchiveFrame?>(
      future: _future,
      builder: (context, snapshot) {
        final frame = snapshot.data;
        if (frame != null) {
          return ColoredBox(
            color: Colors.black,
            child: Image.file(
              File(frame.imagePath),
              fit: widget.fit,
              alignment: widget.alignment,
              frameBuilder: (context, child, frameIndex, wasSynchronouslyLoaded) {
                if (frameIndex != null || wasSynchronouslyLoaded) _notifyReady(path: frame.imagePath);
                return child;
              },
              errorBuilder: (_, _, _) => _fallback(),
            ),
          );
        }
        return _fallback();
      },
    );
  }

  Widget _fallback() {
    final fallback = widget.fallbackUrl?.trim() ?? '';
    if (fallback.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyReady());
      return const ColoredBox(color: Colors.black);
    }
    if (PrismSeedMediaStore.instance.hasUrlSync(fallback)) {
      return PrismSeedMediaImage(
        url: fallback,
        fit: widget.fit,
        alignment: widget.alignment,
        placeholder: (_) => const ColoredBox(color: Colors.black),
        errorWidget: (_) {
          _notifyReady();
          return const ColoredBox(color: Colors.black);
        },
        onReady: _notifyReady,
      );
    }
    return CachedNetworkImage(
      imageUrl: fallback,
      fit: widget.fit,
      alignment: widget.alignment,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      imageBuilder: (context, provider) {
        _notifyReady();
        return SizedBox.expand(child: Image(image: provider, fit: widget.fit, alignment: widget.alignment));
      },
      placeholder: (_, _) => const ColoredBox(color: Colors.black),
      errorWidget: (_, _, _) {
        _notifyReady();
        return const ColoredBox(color: Colors.black);
      },
    );
  }
}
