import 'dart:async';

import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/features/charging_animations/data/charging_animation_selection_store.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

@RoutePage()
class ChargingAnimationPlayerScreen extends StatefulWidget {
  const ChargingAnimationPlayerScreen({super.key});

  @override
  State<ChargingAnimationPlayerScreen> createState() => _ChargingAnimationPlayerScreenState();
}

class _ChargingAnimationPlayerScreenState extends State<ChargingAnimationPlayerScreen> {
  late final ChargingAnimationSelectionStore _selectionStore;
  ChargingAnimationSelection? _selection;
  VideoPlayerController? _controller;
  bool _initializing = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _selectionStore = ChargingAnimationSelectionStore(getIt<SettingsLocalDataSource>());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(_loadSelection());
  }

  Future<void> _loadSelection() async {
    final selection = _selectionStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _selection = selection;
      _initializing = selection != null;
      _error = null;
    });
    if (selection != null) {
      await _startVideo(selection.videoUrl);
    }
  }

  Future<void> _startVideo(String videoUrl) async {
    final uri = Uri.tryParse(videoUrl.trim());
    if (uri == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        _error = 'invalid_url';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
        _error = null;
      });
    } catch (error) {
      await controller.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (selection?.previewUrl.trim().isNotEmpty == true)
            CachedNetworkImage(imageUrl: selection!.previewUrl, fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.black),
          if (_controller != null && _controller!.value.isInitialized) _CoverVideo(controller: _controller!),
          if (selection == null || _error != null || _initializing)
            DecoratedBox(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: _initializing ? 0.18 : 0.56)),
              child: Center(child: _buildStatus(context)),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filledTonal(
                  onPressed: () {
                    unawaited(context.router.maybePop());
                  },
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.42)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    if (_selection == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Pick a charging animation first.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (_error != null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Unable to play this charging animation.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );
    }
    return const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white));
  }
}

class _CoverVideo extends StatelessWidget {
  const _CoverVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoSize = controller.value.size;
        if (videoSize.width <= 0 || videoSize.height <= 0 || constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final viewAspect = constraints.maxWidth / constraints.maxHeight;
        final videoAspect = videoSize.width / videoSize.height;
        final scale = viewAspect > videoAspect ? viewAspect / videoAspect : videoAspect / viewAspect;
        return Center(
          child: Transform.scale(
            scale: scale,
            child: AspectRatio(aspectRatio: videoAspect, child: VideoPlayer(controller)),
          ),
        );
      },
    );
  }
}
