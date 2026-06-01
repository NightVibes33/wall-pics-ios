import 'dart:convert';
import 'dart:io';

import 'package:Prism/logger/logger.dart';
import 'package:path_provider/path_provider.dart';

enum RemoteStoreOperation { queryGet, docGet, streamSubscribe, set, update, delete, add, transaction }

class RemoteStoreTelemetryEvent {
  const RemoteStoreTelemetryEvent({
    required this.timestamp,
    required this.sourceTag,
    required this.operation,
    required this.collection,
    required this.filtersHash,
    required this.durationMs,
    required this.success,
    this.orderBy,
    this.limit,
    this.resultCount,
    this.docId,
    this.errorCode,
  });

  final DateTime timestamp;
  final String sourceTag;
  final RemoteStoreOperation operation;
  final String collection;
  final String filtersHash;
  final List<String>? orderBy;
  final int? limit;
  final int durationMs;
  final int? resultCount;
  final String? docId;
  final bool success;
  final String? errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'timestamp': timestamp.toUtc().toIso8601String(),
    'sourceTag': sourceTag,
    'operation': operation.name,
    'collection': collection,
    'filtersHash': filtersHash,
    'orderBy': orderBy,
    'limit': limit,
    'durationMs': durationMs,
    'resultCount': resultCount,
    'docId': docId,
    'success': success,
    'errorCode': errorCode,
  };
}

abstract class RemoteStoreTelemetrySink {
  Future<void> emit(RemoteStoreTelemetryEvent event);
}

class RemoteStoreConsoleTelemetrySink implements RemoteStoreTelemetrySink {
  const RemoteStoreConsoleTelemetrySink();

  @override
  Future<void> emit(RemoteStoreTelemetryEvent event) async {
    logger.i('[RemoteStore]', tag: 'RemoteStore', fields: event.toJson());
  }
}

class RemoteStoreFileTelemetrySink implements RemoteStoreTelemetrySink {
  RemoteStoreFileTelemetrySink({this.fileName = 'remote_store_telemetry.ndjson'});

  final String fileName;
  File? _file;

  /// Serializes appends so concurrent emit() calls cannot interleave and corrupt NDJSON.
  Future<void> _writeTail = Future<void>.value();

  Future<File> _resolveFile() async {
    if (_file != null) {
      return _file!;
    }
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}/$fileName');
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    _file = file;
    return file;
  }

  @override
  Future<void> emit(RemoteStoreTelemetryEvent event) {
    final prev = _writeTail;
    late Future<void> next;
    next = prev.then((_) async {
      // Only write valid event JSON from toJson(); never raw or partial data.
      final String line = '${jsonEncode(event.toJson())}\n';
      final File file = await _resolveFile();
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    });
    _writeTail = next;
    return next;
  }
}

class CompositeRemoteStoreTelemetrySink implements RemoteStoreTelemetrySink {
  CompositeRemoteStoreTelemetrySink(this._sinks);

  final List<RemoteStoreTelemetrySink> _sinks;

  @override
  Future<void> emit(RemoteStoreTelemetryEvent event) async {
    for (final RemoteStoreTelemetrySink sink in _sinks) {
      await sink.emit(event);
    }
  }
}
