import 'package:Prism/core/persistence/local_store.dart';
import 'package:Prism/core/persistence/persistence_keys.dart';

class PersistenceMigrationRunner {
  const PersistenceMigrationRunner._();

  static Future<void> run(LocalStore store) async {
    final version = _intValue(store.get(PersistenceKeys.schemaVersion)) ?? 0;
    if (version < PersistenceKeys.currentSchemaVersion) {
      await _migrateToV3(store);
    }
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static Set<String> _stringSet(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toSet();
    }
    if (value is String && value.isNotEmpty) {
      return <String>{value};
    }
    return <String>{};
  }

  /// v→3: consolidate per-item favorite keys into set-based keys, and remove
  /// stale large-payload keys from SharedPreferences (feed cache, icon cache,
  /// notifications — these now live in JSON files via LazyFileCache).
  static Future<void> _migrateToV3(LocalStore store) async {
    final allKeys = await store.keys();

    // 1. Consolidate wall favorites: favorites.walls.<scope>.<itemId> → set key
    final wallKeys = allKeys.where((k) => k.startsWith(PersistenceKeys.favoritesWallPrefix)).toList();
    final wallsByScope = <String, Set<String>>{};
    for (final key in wallKeys) {
      // Key format: favorites.walls.<scope>.<itemId>
      // Skip the new set-based keys (contain '__set.')
      if (key.contains('__set.')) continue;
      final withoutPrefix = key.substring(PersistenceKeys.favoritesWallPrefix.length);
      final dotIndex = withoutPrefix.indexOf('.');
      if (dotIndex < 0) continue;
      final scope = withoutPrefix.substring(0, dotIndex);
      final itemId = withoutPrefix.substring(dotIndex + 1);
      wallsByScope.putIfAbsent(scope, () => <String>{}).add(itemId);
    }
    for (final entry in wallsByScope.entries) {
      final setKey = PersistenceKeys.favoritesWallSet(entry.key);
      final existingSet = _stringSet(store.get(setKey));
      existingSet.addAll(entry.value);
      await store.set(setKey, existingSet.toList(growable: false));
    }
    // Delete all old per-item wall favorite keys.
    for (final key in wallKeys) {
      if (!key.contains('__set.')) {
        await store.delete(key);
      }
    }

    // 2. Consolidate setup favorites: favorites.setups.<scope>.<itemId> → set key
    final setupKeys = allKeys.where((k) => k.startsWith(PersistenceKeys.favoritesSetupPrefix)).toList();
    final setupsByScope = <String, Set<String>>{};
    for (final key in setupKeys) {
      if (key.contains('__set.')) continue;
      final withoutPrefix = key.substring(PersistenceKeys.favoritesSetupPrefix.length);
      final dotIndex = withoutPrefix.indexOf('.');
      if (dotIndex < 0) continue;
      final scope = withoutPrefix.substring(0, dotIndex);
      final itemId = withoutPrefix.substring(dotIndex + 1);
      setupsByScope.putIfAbsent(scope, () => <String>{}).add(itemId);
    }
    for (final entry in setupsByScope.entries) {
      final setKey = PersistenceKeys.favoritesSetupSet(entry.key);
      final existingSet = _stringSet(store.get(setKey));
      existingSet.addAll(entry.value);
      await store.set(setKey, existingSet.toList(growable: false));
    }
    for (final key in setupKeys) {
      if (!key.contains('__set.')) {
        await store.delete(key);
      }
    }

    // 3. Remove stale large-payload keys from SharedPreferences.
    //    These now live in JSON files via LazyFileCache.
    await store.clearPrefix(PersistenceKeys.cacheFeedPrefix);
    await store.delete(PersistenceKeys.cacheIconsAppsPayload);
    await store.delete(PersistenceKeys.cacheIconsAppsUpdatedAtUtc);
    await store.delete(PersistenceKeys.notificationsItems);

    // 4. Stamp the new schema version.
    await store.set(PersistenceKeys.schemaVersion, 3);
    await store.set(PersistenceKeys.schemaMigratedAtUtc, DateTime.now().toUtc().toIso8601String());
  }
}
