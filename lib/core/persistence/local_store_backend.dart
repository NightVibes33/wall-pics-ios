enum LocalStoreBackend { sharedPrefs, memory }

extension LocalStoreBackendX on LocalStoreBackend {
  static LocalStoreBackend fromDefine(String raw) {
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'memory':
      case 'in_memory':
      case 'inmemory':
        return LocalStoreBackend.memory;
      case 'shared_prefs':
      case 'sharedprefs':
      case 'sharedpreferences':
      default:
        return LocalStoreBackend.sharedPrefs;
    }
  }
}
