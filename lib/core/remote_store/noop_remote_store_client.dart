import 'dart:async';

import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';

class NoopRemoteStoreTransaction implements RemoteStoreTransaction {
  @override
  Future<Map<String, dynamic>?> getDoc(String collection, String id) async => null;

  @override
  void setDoc(String collection, String id, Map<String, dynamic> data, {bool merge = false}) {}

  @override
  void updateDoc(String collection, String id, Map<String, dynamic> data) {}

  @override
  void deleteDoc(String collection, String id) {}
}

class NoopRemoteStoreBatch implements RemoteStoreBatch {
  @override
  void addDoc(String collection, Map<String, dynamic> data) {}

  @override
  void updateDoc(String collection, String id, Map<String, dynamic> data) {}

  @override
  void deleteDoc(String collection, String id) {}
}

class NoopRemoteStoreClient implements RemoteStoreClient {
  const NoopRemoteStoreClient();

  @override
  Future<List<T>> query<T>(RemoteStoreQuerySpec spec, T Function(Map<String, dynamic> data, String docId) map) async {
    return <T>[];
  }

  @override
  Future<T?> getById<T>(
    String collection,
    String id,
    T Function(Map<String, dynamic> data, String docId) map, {
    required String sourceTag,
    bool preferCacheFirst = false,
  }) async {
    return null;
  }

  @override
  Future<void> setDoc(
    String collection,
    String id,
    Map<String, dynamic> data, {
    bool merge = false,
    required String sourceTag,
  }) async {}

  @override
  Future<void> updateDoc(String collection, String id, Map<String, dynamic> data, {required String sourceTag}) async {}

  @override
  Future<void> deleteDoc(String collection, String id, {required String sourceTag}) async {}

  @override
  Future<String> addDoc(String collection, Map<String, dynamic> data, {required String sourceTag}) async {
    return 'local-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Stream<List<T>> watchQuery<T>(RemoteStoreQuerySpec spec, T Function(Map<String, dynamic> data, String docId) map) {
    return Stream<List<T>>.value(<T>[]);
  }

  @override
  Future<T> runTransaction<T>(
    Future<T> Function(RemoteStoreTransaction transaction) action, {
    required String sourceTag,
    required String collection,
    String? docId,
  }) {
    return action(NoopRemoteStoreTransaction());
  }

  @override
  Future<void> runBatch(Future<void> Function(RemoteStoreBatch batch) action, {required String sourceTag}) {
    return action(NoopRemoteStoreBatch());
  }
}
