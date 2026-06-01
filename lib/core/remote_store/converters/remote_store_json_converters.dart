import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

class RemoteStoreDateTimeConverter implements JsonConverter<DateTime?, Object?> {
  const RemoteStoreDateTimeConverter();

  @override
  DateTime? fromJson(Object? json) {
    if (json == null) return null;
    if (json is DateTime) return json;
    if (json is String) return DateTime.tryParse(json);
    if (json is int) return DateTime.fromMillisecondsSinceEpoch(json, isUtc: true);
    return null;
  }

  @override
  Object? toJson(DateTime? object) => object;
}

class RemoteStoreStringConverter implements JsonConverter<String, Object?> {
  const RemoteStoreStringConverter();

  @override
  String fromJson(Object? json) {
    if (json == null) return '';
    if (json is String) return json;
    if (json is List) return jsonEncode(json);
    return json.toString();
  }

  @override
  Object? toJson(String object) => object;
}

class RemoteStoreStringListConverter implements JsonConverter<List<String>, Object?> {
  const RemoteStoreStringListConverter();

  @override
  List<String> fromJson(Object? json) {
    if (json is! List) return const <String>[];
    return json.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList(growable: false);
  }

  @override
  Object? toJson(List<String> object) => object;
}

class RemoteStoreStringMapConverter implements JsonConverter<Map<String, String>, Object?> {
  const RemoteStoreStringMapConverter();

  @override
  Map<String, String> fromJson(Object? json) {
    if (json is! Map) return const <String, String>{};
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<Object?, Object?> entry in json.entries) {
      final String key = entry.key?.toString() ?? '';
      if (key.isEmpty || entry.value == null) {
        continue;
      }
      result[key] = entry.value.toString();
    }
    return result;
  }

  @override
  Object? toJson(Map<String, String> object) => object;
}

class RemoteStoreJsonMapConverter implements JsonConverter<Map<String, Object?>, Object?> {
  const RemoteStoreJsonMapConverter();

  @override
  Map<String, Object?> fromJson(Object? json) {
    if (json is! Map) return const <String, Object?>{};
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in json.entries) {
      final String key = entry.key?.toString() ?? '';
      if (key.isEmpty) {
        continue;
      }
      result[key] = entry.value;
    }
    return result;
  }

  @override
  Object? toJson(Map<String, Object?> object) => object;
}
