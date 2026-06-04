import 'package:Prism/core/persistence/local_store.dart';
import 'package:Prism/core/persistence/local_store_backend.dart';
import 'package:Prism/core/persistence/migrations/persistence_migration_runner.dart';
import 'package:Prism/core/persistence/persistence_runtime.dart';
import 'package:Prism/core/persistence/store_adapters/memory_store_adapter.dart';
import 'package:Prism/core/persistence/store_adapters/shared_prefs_store_adapter.dart';
import 'package:Prism/env/env.dart';

class PersistenceBootstrap {
  PersistenceBootstrap._();

  static Future<void> initialize() async {
    final LocalStoreBackend backend = LocalStoreBackendX.fromDefine(Env.localPersistenceBackend);

    final LocalStore store = _storeForBackend(backend);

    try {
      await store.init();
      await PersistenceMigrationRunner.run(store);
      PersistenceRuntime.initialize(store: store, backend: backend);
    } catch (_) {
      final LocalStore fallbackStore = MemoryStoreAdapter();
      await fallbackStore.init();
      PersistenceRuntime.initialize(store: fallbackStore, backend: LocalStoreBackend.memory);
    }
  }

  static LocalStore _storeForBackend(LocalStoreBackend backend) {
    switch (backend) {
      case LocalStoreBackend.sharedPrefs:
        return SharedPrefsStoreAdapter();
      case LocalStoreBackend.memory:
        return MemoryStoreAdapter();
    }
  }
}
