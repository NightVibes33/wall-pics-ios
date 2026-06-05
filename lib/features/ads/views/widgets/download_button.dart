import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/interaction/prism_haptics.dart';
import 'package:Prism/core/interaction/prism_tap_scale.dart';
import 'package:Prism/core/platform/pigeon/prism_media_api.g.dart';
import 'package:Prism/core/platform/wallpaper_capability.dart';
import 'package:Prism/core/purchases/download_access_service.dart';
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
    this.isLivePhoto = false,
    this.livePhotoStillUrl,
    this.livePhotoTimeSeconds,
    super.key,
  });

  final String? link;
  final bool colorChanged;
  final bool isPremiumContent;
  final String? contentId;
  final String? sourceContext;
  final bool isLivePhoto;
  final String? livePhotoStillUrl;
  final double? livePhotoTimeSeconds;

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return PrismTapScale(
      pressedScale: 0.92,
      enabled: !_isLoading,
      child: GestureDetector(
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
      ),
    );
  }


  Future<void> _handleTap() async {
    if (_isLoading) {
      PrismHaptics.warning();
      toasts.error('Wait for download to complete!');
      return;
    }

    final String link = widget.link?.trim() ?? '';
    if (link.isEmpty) {
      PrismHaptics.failure();
      toasts.error('No download link available.');
      return;
    }

    PrismHaptics.mediumImpact();
    await _performDownload();
  }

  bool _isLocalMediaPath(String link) {
    return link.startsWith('/') || link.startsWith('file://') || link.contains('com.hash.prism');
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
      PrismHaptics.failure();
      toasts.error('No download link available.');
      return false;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final sourceContext = widget.sourceContext ?? 'download_button';
      final contentId = widget.contentId ?? _filenameBaseFromUrl(link);
      if (widget.isLivePhoto && (widget.livePhotoStillUrl?.trim().isEmpty ?? true)) {
        PrismHaptics.failure();
        toasts.error('This source is missing an original Live Photo still.');
        return false;
      }

      final canStartDownload = await DownloadAccessService.instance.ensureCanStartDownload(
        context,
        sourceContext: sourceContext,
        isPremiumContent: widget.isPremiumContent,
      );
      if (!canStartDownload) {
        return false;
      }

      var savedLivePhoto = false;
      logger.d(link);
      final shouldSaveLivePhoto = widget.isLivePhoto;
      if (shouldSaveLivePhoto) {
        final stillUrl = widget.livePhotoStillUrl?.trim();
        final message = await PrismLivePhotoSaver.save(
          videoUrl: link,
          stillUrl: stillUrl,
          photoTimeSeconds: widget.livePhotoTimeSeconds,
        ).timeout(const Duration(seconds: 180));
        if (message != null) {
          PrismHaptics.failure();
          toasts.error(message);
          return false;
        }
        savedLivePhoto = true;
      } else if (hideSetWallpaperUi || _isLocalMediaPath(link)) {
        final OperationResult result = await PrismMediaHostApi()
            .saveMedia(
              SaveMediaRequest(
                link: link,
                isLocalFile: _isLocalMediaPath(link),
                kind: SaveMediaKind.wallpaper,
              ),
            )
            .timeout(const Duration(seconds: 60));
        if (!result.success) {
          PrismHaptics.failure();
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
          PrismHaptics.failure();
          toasts.error(result.message ?? "Couldn't download! Please retry.");
          return false;
        }
      }

      final claimed = await DownloadAccessService.instance.claimSuccessfulFreeDownload(
        contentId: contentId,
        sourceContext: sourceContext,
      );
      if (!claimed) {
        return false;
      }

      analytics.track(
        DownloadWallpaperEvent(
          link: link,
          sourceContext: sourceContext.trim().isEmpty ? null : sourceContext,
          premiumContent: widget.isPremiumContent,
        ),
      );
      if (mounted) {
        await NotificationPermissionPromptService.instance.maybePromptAfterValueAction(
          context,
          sourceTag: 'notifications.permission_after_download',
        );
      }
      PrismHaptics.success();
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
      PrismHaptics.failure();
      toasts.error("Couldn't download! Please retry.");
      return false;
    } catch (e) {
      logger.e('Unexpected download failure', error: e);
      PrismHaptics.failure();
      toasts.error('Something went wrong!');
      return false;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
