import 'dart:typed_data';

import 'package:Prism/features/prism_catalog/data/prism_seed_media_store.dart';
import 'package:flutter/material.dart';

class PrismSeedMediaImage extends StatefulWidget {
  const PrismSeedMediaImage({
    required this.url,
    required this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.high,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholder,
    this.errorWidget,
    this.onReady,
    super.key,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final int? cacheWidth;
  final int? cacheHeight;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final VoidCallback? onReady;

  @override
  State<PrismSeedMediaImage> createState() => _PrismSeedMediaImageState();
}

class _PrismSeedMediaImageState extends State<PrismSeedMediaImage> {
  Uint8List? _bytes;
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PrismSeedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _load();
    }
  }

  void _load() {
    final syncBytes = PrismSeedMediaStore.instance.bytesForUrlSync(widget.url);
    if (syncBytes != null) {
      _bytes = syncBytes;
      _future = null;
      _notifyReady();
      return;
    }
    _future = PrismSeedMediaStore.instance.bytesForUrl(widget.url);
  }

  void _notifyReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return _image(bytes);
    }
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded != null && loaded.isNotEmpty) {
          _bytes = loaded;
          _notifyReady();
          return _image(loaded);
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return widget.errorWidget?.call(context) ?? widget.placeholder?.call(context) ?? const SizedBox.shrink();
        }
        return widget.placeholder?.call(context) ?? const SizedBox.shrink();
      },
    );
  }

  Widget _image(Uint8List bytes) {
    return Image.memory(
      bytes,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
    );
  }
}
