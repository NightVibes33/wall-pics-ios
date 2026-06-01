class RemoteStoreSentinels {
  const RemoteStoreSentinels._();

  static Object arrayUnion(List<Object?> values) => <String, Object?>{'op': 'arrayUnion', 'values': values};
  static Object arrayRemove(List<Object?> values) => <String, Object?>{'op': 'arrayRemove', 'values': values};
}
