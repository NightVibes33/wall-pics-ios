import 'package:Prism/core/persistence/local_store.dart';

class MemoryStoreAdapter implements LocalStore {
  final Map<String, Object?> _values = <String, Object?>{};
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<void> init() async {
    _ready = true;
  }

  @override
  Object? get(String key) {
    return _values[key];
  }

  @override
  Future<void> set(String key, Object? value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<List<String>> keys() async {
    return _values.keys.toList(growable: false);
  }

  @override
  Future<void> clearPrefix(String prefix) async {
    _values.removeWhere((String key, Object? _) => key.startsWith(prefix));
  }

  @override
  Future<void> clearAll() async {
    _values.clear();
  }
}
