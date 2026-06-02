import 'dart:convert';

import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';

class ChargingAnimationSelection {
  const ChargingAnimationSelection({
    required this.id,
    required this.name,
    required this.videoUrl,
    required this.previewUrl,
  });

  final String id;
  final String name;
  final String videoUrl;
  final String previewUrl;

  bool get isPlayable => videoUrl.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'videoUrl': videoUrl,
    'previewUrl': previewUrl,
  };

  static ChargingAnimationSelection? fromJson(Object? value) {
    if (value == null) {
      return null;
    }
    try {
      final Object? decoded = value is String ? jsonDecode(value) : value;
      if (decoded is! Map) {
        return null;
      }
      final map = decoded.map<String, Object?>((key, val) => MapEntry(key.toString(), val));
      final videoUrl = map['videoUrl']?.toString().trim() ?? '';
      if (videoUrl.isEmpty) {
        return null;
      }
      return ChargingAnimationSelection(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        videoUrl: videoUrl,
        previewUrl: map['previewUrl']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class ChargingAnimationSelectionStore {
  const ChargingAnimationSelectionStore(this._settingsLocal);

  static const String key = 'charging_animation.selected';

  final SettingsLocalDataSource _settingsLocal;

  ChargingAnimationSelection? load() {
    final raw = _settingsLocal.get<Object?>(key, defaultValue: null, hasDefault: true);
    return ChargingAnimationSelection.fromJson(raw);
  }

  Future<void> save(ChargingAnimationSelection selection) {
    return _settingsLocal.set(key, jsonEncode(selection.toJson()));
  }

  Future<void> clear() {
    return _settingsLocal.delete(key);
  }
}
