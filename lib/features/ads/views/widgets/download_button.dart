import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/platform/pigeon/prism_media_api.g.dart';
import 'package:Prism/core/platform/wallpaper_capability.dart';
import 'package:Prism/core/platform/prism_live_photo_saver.dart';
import 'package:Prism/features/startup/services/notification_permission_prompt_service.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DownloadButton extends StatefulWidget {
  const DownloadButton({
    required this.link,
    required this.colorChanged,
    this.isPremiumContent = false,
    this.contentId,
    this.sourceContext,
    this.livePhotoStillUrl,
    super.key,
  });

  final String? link;
  final bool colorChanged;
  final bool isPremiumContent;
  final String? contentId;
  final String? sourceContext;
  final String? livePhotoStillUrl;

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 4, offset: const Offset(0, 4)),
              ],
              borderRadius: BorderRadius.circular(500),
            ),
            padding: const EdgeInsets.all(17),
            child: Icon(JamIcons.download, color: Theme.of(context).colorScheme.secondary, size: 20),
          ),
          Positioned(
            top: 0,
            left: 0,
            height: 53,
            width: 53,
            child: _isLoading ? const CircularProgressIndicator() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTap() async {
    if (_isLoading) {
      toasts.error('Wait for download to complete!');
      return;
    }

    final String link = widget.link?.trim() ?? '';
    if (link.isEmpty) {
      toasts.error('No download link available.');
      return;
    }

    await _performDownload();
  }

  bool _isLivePhotoVideo(String link) {
    final path = Uri.tryParse(link)?.path.toLowerCase() ?? link.toLowerCase();
    return path.endsWith('.mp4') || path.endsWith('.mov');
  }

  String _filenameBaseFromUrl(String link) {
    final uri = Uri.tryParse(link);
    final rawName = uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : link.split('/').last;
    final withoutQuery = rawName.split('?').first;
    return withoutQuery.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  }

  Future<bool> _performDownload() async {
    final String link = widget.link?.trim() ?? '';
    if (link.isEmpty) {
      toasts.error('No download link available.');
      return false;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      var savedLivePhoto = false;
      logger.d(link);
      if (_isLivePhotoVideo(link)) {
        final stillUrl = widget.livePhotoStillUrl?.trim();
        final message = await PrismLivePhotoSaver.save(
          videoUrl: link,
          stillUrl: stillUrl,
        ).timeout(const Duration(seconds: 45));
        if (message != null) {
          toasts.error(message);
          return false;
        }
        savedLivePhoto = true;
      } else if (hideSetWallpaperUi || link.contains('com.hash.prism')) {
        final OperationResult result = await PrismMediaHostApi()
            .saveMedia(
              SaveMediaRequest(
                link: link,
                isLocalFile: link.contains('com.hash.prism'),
                kind: SaveMediaKind.wallpaper,
              ),
            )
            .timeout(const Duration(seconds: 60));
        if (!result.success) {
          toasts.error("Couldn't download! Please retry.");
          return false;
        }
      } else {
        final DownloadRequest request = DownloadRequest(
          link: link,
          filenameWithoutExtension: _filenameBaseFromUrl(link),
        );
        final OperationResult result = await PrismMediaHostApi().enqueueDownload(request).timeout(const Duration(seconds: 15));
        if (!result.success) {
          toasts.error(result.message ?? "Couldn't download! Please retry.");
          return false;
        }
      }

      analytics.track(
        DownloadWallpaperEvent(
          link: link,
          sourceContext: (widget.sourceContext ?? '').trim().isEmpty ? null : widget.sourceContext,
          premiumContent: false,
        ),
      );
      if (mounted) {
        await NotificationPermissionPromptService.instance.maybePromptAfterValueAction(
          context,
          sourceTag: 'notifications.permission_after_download',
        );
      }
      toasts.codeSend(
        savedLivePhoto ? 'Live Photo saved to Photos.' : (hideSetWallpaperUi ? 'Saved to Photos.' : 'Wall downloaded in Pictures/Prism!'),
      );
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'channel-error') {
        logger.w('Download channel unavailable (native side not registered)', error: e);
      } else {
        logger.e('Download failed', error: e);
      }
      toasts.error("Couldn't download! Please retry.");
      return false;
    } catch (e) {
      logger.e('Unexpected download failure', error: e);
      toasts.error('Something went wrong!');
      return false;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
