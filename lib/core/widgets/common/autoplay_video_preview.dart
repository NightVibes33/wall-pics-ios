import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AutoplayVideoPreview extends StatefulWidget {
  const AutoplayVideoPreview({
    required this.videoUrl,
    this.posterUrl,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.muted = true,
    this.onReady,
    super.key,
  });

  final String videoUrl;
  final String? posterUrl;
  final BoxFit fit;
  final Alignment alignment;
  final bool muted;
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
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  Future<void> _load() async {
    final rawUrl = widget.videoUrl.trim();
    final generation = ++_loadGeneration;
    final oldController = _controller;
    _controller = null;
    _failed = false;
    if (oldController != null) {
      unawaited(oldController.dispose());
    }
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

    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setLooping(true);
      if (widget.muted) {
        await controller.setVolume(0);
      }
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      unawaited(controller.play());
      widget.onReady?.call();
    } catch (_) {
      await controller.dispose();
      if (mounted && generation == _loadGeneration) {
        setState(() => _failed = true);
      }
      widget.onReady?.call();
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
    return CachedNetworkImage(
      imageUrl: poster,
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
