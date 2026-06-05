import 'dart:async';
import 'dart:io';

import 'package:Prism/features/prism_catalog/data/prism_seed_media_store.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AutoplayVideoPreview extends StatefulWidget {
  const AutoplayVideoPreview({
    required this.videoUrl,
    this.posterUrl,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.muted = true,
    this.playing = true,
    this.playbackSpeed = 1.0,
    this.onReady,
    super.key,
  });

  final String videoUrl;
  final String? posterUrl;
  final BoxFit fit;
  final Alignment alignment;
  final bool muted;
  final bool playing;
  final double playbackSpeed;
  final VoidCallback? onReady;

  @override
  State<AutoplayVideoPreview> createState() => _AutoplayVideoPreviewState();
}

class _AutoplayVideoPreviewState extends State<AutoplayVideoPreview> {
  VideoPlayerController? _controller;
  int _loadGeneration = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AutoplayVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      unawaited(_load());
    } else {
      unawaited(_syncPlayback());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
  }

  Future<File?> _cachedVideoFile(String url) async {
    try {
      final info = await DefaultCacheManager().getFileFromCache(url).timeout(const Duration(milliseconds: 180));
      final file = info?.file;
      if (file != null && await file.exists()) {
        return file;
      }
    } catch (_) {
      // A cache miss should not delay visible playback.
    }
    return null;
  }

  Future<void> _warmVideoCache(String url) async {
    try {
      await DefaultCacheManager().downloadFile(url).timeout(const Duration(seconds: 30));
    } catch (_) {
      // Video cache warmup is opportunistic; network playback remains active.
    }
  }

  Future<void> _applyPlaybackSpeed(VideoPlayerController controller) async {
    final speed = widget.playbackSpeed.isFinite && widget.playbackSpeed > 0 ? widget.playbackSpeed : 1.0;
    try {
      await controller.setPlaybackSpeed(speed);
    } catch (_) {
      // Some platform player backends do not support speed changes. Keep playback active.
    }
  }

  Future<void> _load() async {
    final rawUrl = widget.videoUrl.trim();
    final generation = ++_loadGeneration;
    _failed = false;
    _disposeController();
    if (mounted) {
      setState(() {});
    }
    if (rawUrl.isEmpty) {
      widget.onReady?.call();
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _failed = true);
      }
      widget.onReady?.call();
      return;
    }

    final cachedFile = await _cachedVideoFile(rawUrl);
    final controller = cachedFile != null ? VideoPlayerController.file(cachedFile) : VideoPlayerController.networkUrl(uri);
    if (cachedFile == null) {
      unawaited(_warmVideoCache(rawUrl));
    }
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      await controller.setLooping(true);
      if (widget.muted) {
        await controller.setVolume(0);
      }
      await _applyPlaybackSpeed(controller);
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await _syncPlayback();
      widget.onReady?.call();
    } catch (_) {
      await controller.dispose();
      if (mounted && generation == _loadGeneration) {
        setState(() => _failed = true);
      }
      widget.onReady?.call();
    }
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (widget.muted) {
      await controller.setVolume(0);
    }
    await _applyPlaybackSpeed(controller);
    if (widget.playing) {
      if (!controller.value.isPlaying) {
        await controller.play();
      }
    } else if (controller.value.isPlaying) {
      await controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo = controller != null && controller.value.isInitialized && !_failed;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _poster(context),
          if (showVideo) _video(controller),
        ],
      ),
    );
  }

  Widget _poster(BuildContext context) {
    final poster = widget.posterUrl?.trim() ?? '';
    if (poster.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    final seedBytes = PrismSeedMediaStore.instance.bytesForUrlSync(poster);
    if (seedBytes != null) {
      widget.onReady?.call();
      return Image.memory(
        seedBytes,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: FilterQuality.high,
      );
    }
    return CachedNetworkImage(
      imageUrl: poster,
      imageBuilder: (context, imageProvider) {
        widget.onReady?.call();
        return SizedBox.expand(child: Image(image: imageProvider, fit: widget.fit, alignment: widget.alignment));
      },
      fit: widget.fit,
      alignment: widget.alignment,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (_, _) => const ColoredBox(color: Colors.black),
      errorWidget: (_, _, _) => const ColoredBox(color: Colors.black),
    );
  }

  Widget _video(VideoPlayerController controller) {
    final size = controller.value.size;
    final width = size.width > 0 ? size.width : 9.0;
    final height = size.height > 0 ? size.height : 16.0;
    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        alignment: widget.alignment,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
