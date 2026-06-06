import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class PrismSeedMediaStore {
  PrismSeedMediaStore._();

  static final PrismSeedMediaStore instance = PrismSeedMediaStore._();

  static const String _assetPath = 'assets/catalog/prism_seed_media.dbx';
  static const String _manifestAssetPath = 'assets/catalog/prism_seed_media_manifest.json';
  static const List<int> _magic = <int>[0x50, 0x53, 0x4d, 0x45, 0x44, 0x49, 0x41, 0x31, 0x0a];
  static const List<int> _binaryMagic = <int>[0x50, 0x53, 0x4d, 0x42, 0x49, 0x4e, 0x32, 0x0a];
  static const List<int> _keyParts = <int>[
    0x2a, 0x28, 0x33, 0x29, 0x37, 0x77, 0x39, 0x3b, 0x2e, 0x3b, 0x36, 0x35, 0x3d, 0x77, 0x29, 0x3f,
    0x3f, 0x3e, 0x77, 0x37, 0x3f, 0x3e, 0x33, 0x3b, 0x77, 0x2c, 0x6b,
  ];

  static const int _maxMemoryCacheBytes = 96 * 1024 * 1024;

  final Map<String, Uint8List> _mediaByKey = <String, Uint8List>{};
  final Map<String, _SeedMediaEntry> _entriesByKey = <String, _SeedMediaEntry>{};
  final Map<String, Uint8List> _decodedBytesByKey = <String, Uint8List>{};
  final List<String> _decodedByteOrder = <String>[];
  final Map<String, Future<Uint8List?>> _byteLoadsByKey = <String, Future<Uint8List?>>{};
  final Map<String, Future<File?>> _fileLoadsByKey = <String, Future<File?>>{};
  int _decodedMemoryBytes = 0;
  Future<void>? _warmFuture;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> warm() {
    return _warmFuture ??= _load();
  }

  bool hasUrlSync(String url) {
    if (!_loaded) {
      return false;
    }
    return _entryForUrl(url) != null || bytesForUrlSync(url) != null;
  }

  Uint8List? bytesForUrlSync(String url) {
    if (!_loaded) {
      return null;
    }
    for (final key in _candidateKeys(url)) {
      final cached = _decodedBytesByKey[key];
      if (cached != null && cached.isNotEmpty) {
        _touchDecodedKey(key);
        return cached;
      }
      final legacyBytes = _mediaByKey[key];
      if (legacyBytes != null && legacyBytes.isNotEmpty) {
        return legacyBytes;
      }
    }
    return null;
  }

  Future<Uint8List?> bytesForUrl(String url) async {
    await warm();
    final sync = bytesForUrlSync(url);
    if (sync != null) {
      return sync;
    }
    final match = _entryMatchForUrl(url);
    if (match == null || !match.entry.isImage) {
      return null;
    }
    return _byteLoadsByKey.putIfAbsent(match.key, () async {
      try {
        final raw = await rootBundle.load(match.entry.asset);
        final bytes = _crypt(raw.buffer.asUint8List());
        _rememberDecodedBytes(match.key, bytes);
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _byteLoadsByKey.remove(match.key);
      }
    });
  }

  Future<File?> fileForUrl(String url) async {
    await warm();
    final match = _entryMatchForUrl(url);
    if (match != null) {
      return _fileLoadsByKey.putIfAbsent(match.key, () async {
        try {
          final tempDir = await getTemporaryDirectory();
          final directory = Directory('${tempDir.path}/prism_seed_media');
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
          final extension = match.entry.extension.isNotEmpty ? match.entry.extension : _extensionForUrl(url);
          final file = File('${directory.path}/${match.key}$extension');
          if (await file.exists() && await file.length() == match.entry.length) {
            return file;
          }
          final raw = await rootBundle.load(match.entry.asset);
          final bytes = _crypt(raw.buffer.asUint8List());
          await file.writeAsBytes(bytes, flush: false);
          return file;
        } catch (_) {
          return null;
        } finally {
          _fileLoadsByKey.remove(match.key);
        }
      });
    }

    final legacyBytes = bytesForUrlSync(url);
    if (legacyBytes == null || legacyBytes.isEmpty) {
      return null;
    }
    final key = cacheKeyForUrl(url);
    return _fileLoadsByKey.putIfAbsent(key, () async {
      try {
        final tempDir = await getTemporaryDirectory();
        final directory = Directory('${tempDir.path}/prism_seed_media');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final file = File('${directory.path}/$key${_extensionForUrl(url)}');
        if (!await file.exists()) {
          await file.writeAsBytes(legacyBytes, flush: false);
        }
        return file;
      } catch (_) {
        return null;
      } finally {
        _fileLoadsByKey.remove(key);
      }
    });
  }

  Future<void> _load() async {
    await _loadManifestPack();
    if (_entriesByKey.isNotEmpty) {
      _loaded = true;
      return;
    }
    try {
      final rawData = await rootBundle.load(_assetPath);
      final raw = rawData.buffer.asUint8List();
      if (raw.length <= _magic.length || !_hasMagic(raw)) {
        _loaded = true;
        return;
      }
      final encrypted = raw.sublist(_magic.length);
      final plain = _crypt(encrypted);
      if (_hasBinaryMagic(plain)) {
        _loadBinaryPack(plain);
      } else {
        _loadJsonPack(plain);
      }
    } catch (_) {
      // Seed packs are optional. Missing or unreadable seed data falls back to the network cache.
    } finally {
      _loaded = true;
    }
  }


  Future<void> _loadManifestPack() async {
    try {
      final raw = await rootBundle.loadString(_manifestAssetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final entries = decoded['entries'];
      if (entries is! List) {
        return;
      }
      for (final entry in entries) {
        if (entry is! Map) {
          continue;
        }
        final mediaEntry = _SeedMediaEntry.fromJson(entry);
        if (mediaEntry == null) {
          continue;
        }
        _entriesByKey[mediaEntry.key] = mediaEntry;
      }
    } catch (_) {
      // Manifest packs are generated in CI. Local/dev builds may only have the legacy DBX placeholder.
    }
  }

  void _loadBinaryPack(Uint8List plain) {
    const headerLength = 8;
    const indexLengthBytes = 4;
    if (plain.length < headerLength + indexLengthBytes) {
      return;
    }
    final byteData = ByteData.sublistView(plain);
    final indexLength = byteData.getUint32(headerLength, Endian.big);
    final indexStart = headerLength + indexLengthBytes;
    final indexEnd = indexStart + indexLength;
    if (indexLength <= 0 || indexEnd > plain.length) {
      return;
    }
    final decoded = jsonDecode(utf8.decode(Uint8List.sublistView(plain, indexStart, indexEnd)));
    if (decoded is! Map) {
      return;
    }
    final entries = decoded['entries'];
    if (entries is! List) {
      return;
    }
    final blobStart = indexEnd;
    for (final entry in entries) {
      if (entry is! Map) {
        continue;
      }
      final key = entry['key']?.toString().trim() ?? '';
      final offset = _intValue(entry['offset']);
      final length = _intValue(entry['length']);
      if (key.isEmpty || offset == null || length == null || offset < 0 || length <= 0) {
        continue;
      }
      final start = blobStart + offset;
      final end = start + length;
      if (start < blobStart || end > plain.length) {
        continue;
      }
      _mediaByKey[key] = Uint8List.sublistView(plain, start, end);
    }
  }

  void _loadJsonPack(Uint8List plain) {
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map) {
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
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  bool _hasMagic(Uint8List raw) {
    return _startsWith(raw, _magic);
  }

  bool _hasBinaryMagic(Uint8List raw) {
    return _startsWith(raw, _binaryMagic);
  }

  bool _startsWith(Uint8List raw, List<int> prefix) {
    if (raw.length < prefix.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index++) {
      if (raw[index] != prefix[index]) {
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


  _SeedMediaEntry? _entryForUrl(String url) => _entryMatchForUrl(url)?.entry;

  _SeedMediaMatch? _entryMatchForUrl(String url) {
    if (!_loaded || _entriesByKey.isEmpty) {
      return null;
    }
    for (final key in _candidateKeys(url)) {
      final entry = _entriesByKey[key];
      if (entry != null) {
        return _SeedMediaMatch(key: key, entry: entry);
      }
    }
    return null;
  }

  void _rememberDecodedBytes(String key, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxMemoryCacheBytes ~/ 2) {
      return;
    }
    final existing = _decodedBytesByKey[key];
    if (existing != null) {
      _decodedMemoryBytes -= existing.length;
      _decodedByteOrder.remove(key);
    }
    _decodedBytesByKey[key] = bytes;
    _decodedByteOrder.add(key);
    _decodedMemoryBytes += bytes.length;
    while (_decodedMemoryBytes > _maxMemoryCacheBytes && _decodedByteOrder.isNotEmpty) {
      final evicted = _decodedByteOrder.removeAt(0);
      final removed = _decodedBytesByKey.remove(evicted);
      if (removed != null) {
        _decodedMemoryBytes -= removed.length;
      }
    }
  }

  void _touchDecodedKey(String key) {
    if (_decodedBytesByKey.containsKey(key)) {
      _decodedByteOrder.remove(key);
      _decodedByteOrder.add(key);
    }
  }

  String _extensionForUrl(String url) {
    final path = Uri.tryParse(canonicalUrl(url))?.path.toLowerCase() ?? url.toLowerCase();
    for (final extension in const <String>['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4', '.mov', '.zip']) {
      if (path.endsWith(extension)) {
        return extension;
      }
    }
    return '.bin';
  }

  List<String> _candidateKeys(String rawUrl) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) {
      return const <String>[];
    }
    final canonical = canonicalUrl(raw);
    return <String>[_hash(raw), if (canonical != raw) _hash(canonical)];
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


class _SeedMediaEntry {
  const _SeedMediaEntry({
    required this.key,
    required this.asset,
    required this.length,
    required this.extension,
    required this.kind,
  });

  final String key;
  final String asset;
  final int length;
  final String extension;
  final String kind;

  bool get isImage => kind == 'image';

  static _SeedMediaEntry? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final key = raw['key']?.toString().trim() ?? '';
    final asset = raw['asset']?.toString().trim() ?? '';
    final length = raw['length'] is int ? raw['length'] as int : int.tryParse(raw['length']?.toString() ?? '') ?? 0;
    final extension = raw['extension']?.toString().trim() ?? '';
    final kind = raw['kind']?.toString().trim() ?? '';
    if (key.isEmpty || asset.isEmpty || length <= 0 || kind.isEmpty) {
      return null;
    }
    return _SeedMediaEntry(key: key, asset: asset, length: length, extension: extension, kind: kind);
  }
}

class _SeedMediaMatch {
  const _SeedMediaMatch({required this.key, required this.entry});

  final String key;
  final _SeedMediaEntry entry;
}
