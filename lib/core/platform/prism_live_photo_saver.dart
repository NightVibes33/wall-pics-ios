import 'package:flutter/services.dart';

class PrismLivePhotoSaver {
  PrismLivePhotoSaver._();

  static const MethodChannel _channel = MethodChannel('prism/live_photo');

  static Future<String?> save({required String videoUrl, String? stillUrl, double? photoTimeSeconds}) async {
    final result = await _channel.invokeMapMethod<String, Object?>('save', <String, Object?>{
      'videoUrl': videoUrl,
      if (stillUrl != null && stillUrl.trim().isNotEmpty) 'stillUrl': stillUrl.trim(),
      if (photoTimeSeconds != null && photoTimeSeconds >= 0) 'photoTimeSeconds': photoTimeSeconds,
    });
    if (result?['success'] == true) return null;
    return result?['message']?.toString() ?? 'Live Photo could not be saved.';
  }
}
