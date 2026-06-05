import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class PrismSeedMediaStore {
  PrismSeedMediaStore._();

  static final PrismSeedMediaStore instance = PrismSeedMediaStore._();

  static const String _assetPath = 'assets/catalog/prism_seed_media.dbx';
  static const List<int> _magic = <int>[0x50, 0x53, 0x4d, 0x45, 0x44, 0x49, 0x41, 0x31, 0x0a];
  static const List<int> _keyParts = <int>[
    0x2a, 0x28, 0x33, 0x29, 0x37, 0x77, 0x39, 0x3b, 0x2e, 0x3b, 0x36, 0x35, 0x3d, 0x77, 0x29, 0x3f,
    0x3f, 0x3e, 0x77, 0x37, 0x3f, 0x3e, 0x33, 0x3b, 0x77, 0x2c, 0x6b,
  ];

  final Map<String, Uint8List> _mediaByKey = <String, Uint8List>{};
  Future<void>? _warmFuture;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> warm() {
    return _warmFuture ??= _load();
  }

  bool hasUrlSync(String url) {
    return bytesForUrlSync(url) != null;
  }

  Uint8List? bytesForUrlSync(String url) {
    if (!_loaded || _mediaByKey.isEmpty) {
      return null;
    }
    final keys = _candidateKeys(url);
    for (final key in keys) {
      final bytes = _mediaByKey[key];
      if (bytes != null && bytes.isNotEmpty) {
        return bytes;
      }
    }
    return null;
  }

  Future<Uint8List?> bytesForUrl(String url) async {
    await warm();
    return bytesForUrlSync(url);
  }

  Future<void> _load() async {
    try {
      final rawData = await rootBundle.load(_assetPath);
      final raw = rawData.buffer.asUint8List();
      if (raw.length <= _magic.length || !_hasMagic(raw)) {
        _loaded = true;
        return;
      }
      final encrypted = raw.sublist(_magic.length);
      final plain = _crypt(encrypted);
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) {
        _loaded = true;
        return;
      }
      final media = decoded['media'];
      if (media is Map) {
        for (final entry in media.entries) {
          final key = entry.key.toString().trim();
          final value = entry.value?.toString().trim() ?? '';
          if (key.isEmpty || value.isEmpty) {
            continue;
          }
          try {
            final bytes = base64Decode(value);
            if (bytes.isNotEmpty) {
              _mediaByKey[key] = Uint8List.fromList(bytes);
            }
          } catch (_) {
            // Ignore corrupt seed rows; network fallback remains available.
          }
        }
      }
    } catch (_) {
      // Seed packs are optional. Missing or unreadable seed data falls back to the network cache.
    } finally {
      _loaded = true;
    }
  }

  bool _hasMagic(Uint8List raw) {
    if (raw.length < _magic.length) {
      return false;
    }
    for (var index = 0; index < _magic.length; index++) {
      if (raw[index] != _magic[index]) {
        return false;
      }
    }
    return true;
  }

  Uint8List _crypt(Uint8List input) {
    final key = utf8.encode(String.fromCharCodes(_keyParts.map((part) => part ^ 0x5a)));
    final output = Uint8List(input.length);
    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      final blockKey = sha256.convert(<int>[...key, ...utf8.encode(':$counter')]).bytes;
      for (var blockIndex = 0; blockIndex < blockKey.length && offset < input.length; blockIndex++, offset++) {
        output[offset] = input[offset] ^ blockKey[blockIndex];
      }
      counter += 1;
    }
    return output;
  }

  Set<String> _candidateKeys(String rawUrl) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) {
      return const <String>{};
    }
    final canonical = canonicalUrl(raw);
    return <String>{_hash(raw), if (canonical != raw) _hash(canonical)};
  }

  static String canonicalUrl(String rawUrl) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(raw);
    final src = uri?.queryParameters['src']?.trim();
    if (src != null && src.isNotEmpty) {
      return src;
    }
    return raw;
  }

  static String cacheKeyForUrl(String rawUrl) {
    return _hash(canonicalUrl(rawUrl));
  }

  static String _hash(String value) {
    return sha256.convert(utf8.encode(value.trim())).toString();
  }
}
