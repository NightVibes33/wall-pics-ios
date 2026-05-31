import 'package:flutter/services.dart';

class WallpicsLivePhotoSaver {
  WallpicsLivePhotoSaver._();

  static const MethodChannel _channel = MethodChannel('wallpics/live_photo');

  static Future<String?> save({required String videoUrl, required String stillUrl}) async {
    final result = await _channel.invokeMapMethod<String, Object?>('save', <String, Object?>{
      'videoUrl': videoUrl,
      'stillUrl': stillUrl,
    });
    if (result?['success'] == true) return null;
    return result?['message']?.toString() ?? 'Live Photo could not be saved.';
  }
}
