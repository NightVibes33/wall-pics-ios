import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Prism/logger/app_logger.dart';
import 'package:Prism/logger/log_sink.dart';
import 'package:path_provider/path_provider.dart';

/// Persists sanitized app-only logs in the iOS Documents directory.
///
/// The file is intentionally readable from Files/Finder via Info.plist file
/// sharing. Account, auth, network, API, analytics, purchases, and push records
/// are filtered out before they reach disk.
class DocumentLogSink implements LogSink {
  DocumentLogSink._();

  static final DocumentLogSink instance = DocumentLogSink._();

  static const String logFileName = 'Prism-App-Logs.txt';
  static const String previousLogFileName = 'Prism-App-Logs.previous.txt';
  static const int _maxBytes = 8 * 1024 * 1024;
  static const int _maxPendingRecords = 500;

  static final RegExp _blockedTagPattern = RegExp(
    r'(auth|account|github|userstore|network|analytics|sentry|purchase|storekit|push|notification|dynamiclink|api)',
    caseSensitive: false,
  );
  static final RegExp _blockedMessagePattern = RegExp(
    r'(tracking event|sign[ -]?in|sign[ -]?out|signed[ -]?in|signed[ -]?out|account|credential|token|api key|authorization|cookie|github|mixpanel|sentry|purchase|storekit|push|notification)',
    caseSensitive: false,
  );
  static final RegExp _blockedFieldKeyPattern = RegExp(
    r'(auth|account|email|user|token|api|secret|password|cookie|authorization|repo|owner|url|uri|key|credential|client|session)',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(r'https?://[^\s\)\]\}]+', caseSensitive: false);
  static final RegExp _emailPattern = RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);
  static final RegExp _hexSecretPattern = RegExp(r'\b[a-fA-F0-9]{32,}\b');
  static final RegExp _longSecretPattern = RegExp(r'\b[A-Za-z0-9_-]{40,}\b');
  static final RegExp _keyValueSecretPattern = RegExp(
    r'(?i)\b(authorization|bearer|token|api[_ -]?key|secret|password|cookie|client[_ -]?id|credential)\b\s*[:=]\s*[^,\s\}\]]+',
  );

  final List<AppLogRecord> _pending = <AppLogRecord>[];
  Future<File>? _fileFuture;
  Future<void> _writeChain = Future<void>.value();
  bool _flushScheduled = false;
  bool _headerWrittenThisProcess = false;

  Future<String> flushAndGetPath() async {
    _scheduleFlush();
    await _writeChain;
    final File file = await _ensureFile();
    await _writeChain;
    return file.path;
  }

  @override
  void write(AppLogRecord record) {
    if (!_shouldPersist(record)) {
      return;
    }

    if (_pending.length >= _maxPendingRecords) {
      _pending.removeAt(0);
    }
    _pending.add(record);
    _scheduleFlush();
  }

  bool _shouldPersist(AppLogRecord record) {
    final String tag = record.tag ?? '';
    if (tag.isNotEmpty && _blockedTagPattern.hasMatch(tag)) {
      return false;
    }
    if (_blockedMessagePattern.hasMatch(record.message)) {
      return false;
    }
    return true;
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    scheduleMicrotask(() {
      _writeChain = _writeChain.then((_) => _flushPending()).catchError((Object _) {
        _fileFuture = null;
        _flushScheduled = false;
      });
    });
  }

  Future<void> _flushPending() async {
    _flushScheduled = false;
    if (_pending.isEmpty) {
      return;
    }

    final File file = await _ensureFile();
    final List<AppLogRecord> records = List<AppLogRecord>.of(_pending);
    _pending.clear();

    await _rotateIfNeeded(file);

    final StringBuffer buffer = StringBuffer();
    if (!_headerWrittenThisProcess) {
      buffer.write(_sessionHeader());
      _headerWrittenThisProcess = true;
    }
    for (final AppLogRecord record in records) {
      buffer.writeln(_formatRecord(record));
    }

    await file.writeAsString(buffer.toString(), mode: FileMode.append, flush: false);

    if (_pending.isNotEmpty) {
      _scheduleFlush();
    }
  }

  Future<File> _ensureFile() {
    _fileFuture ??= _openFile();
    return _fileFuture!;
  }

  Future<File> _openFile() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File file = File('${directory.path}/$logFileName');
    if (!await file.exists()) {
      await file.writeAsString(_sessionHeader(), flush: true);
      _headerWrittenThisProcess = true;
    }
    return file;
  }

  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) {
      return;
    }
    final int length = await file.length();
    if (length < _maxBytes) {
      return;
    }

    final File previous = File('${file.parent.path}/$previousLogFileName');
    if (await previous.exists()) {
      await previous.delete();
    }
    await file.rename(previous.path);
    await File(file.path).writeAsString(_sessionHeader(), flush: true);
    _headerWrittenThisProcess = true;
  }

  String _sessionHeader() {
    return '\n=== Prism app log session ${DateTime.now().toUtc().toIso8601String()} ===\n'
        'scope=app-only sanitized=true excluded=auth,account,api,network,analytics,purchases,push\n';
  }

  String _formatRecord(AppLogRecord record) {
    final StringBuffer line = StringBuffer()
      ..write(record.timestamp.toUtc().toIso8601String())
      ..write(' ')
      ..write(record.level.shortLabel)
      ..write(' #')
      ..write(record.sequence);

    if (record.tag != null && record.tag!.isNotEmpty) {
      line
        ..write(' [')
        ..write(_sanitizeText(record.tag!))
        ..write(']');
    }

    if (record.spanId != null && record.spanId!.isNotEmpty) {
      line
        ..write(' span=')
        ..write(_sanitizeText(record.spanId!));
    }

    line
      ..write(' ')
      ..write(_sanitizeText(record.message));

    final Map<String, Object?> fields = _sanitizeFields(record.fields);
    if (fields.isNotEmpty) {
      line
        ..write(' fields=')
        ..write(jsonEncode(fields));
    }

    if (record.error != null) {
      line
        ..write(' error=')
        ..write(_sanitizeText(record.error.toString()));
    }

    if (record.stackTrace != null) {
      final String stack = record.stackTrace
          .toString()
          .split('\n')
          .take(12)
          .map(_sanitizeText)
          .join(' | ');
      line
        ..write(' stack=')
        ..write(jsonEncode(stack));
    }

    return line.toString();
  }

  Map<String, Object?> _sanitizeFields(LogFields fields) {
    if (fields.isEmpty) {
      return const <String, Object?>{};
    }

    final Map<String, Object?> sanitized = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in fields.entries) {
      final String key = entry.key;
      if (_blockedFieldKeyPattern.hasMatch(key)) {
        continue;
      }
      sanitized[_sanitizeText(key)] = _sanitizeValue(entry.value);
    }
    return sanitized;
  }

  Object? _sanitizeValue(Object? value) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is Iterable<Object?>) {
      return value.take(20).map(_sanitizeValue).toList(growable: false);
    }
    if (value is Map<Object?, Object?>) {
      final Map<String, Object?> sanitized = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in value.entries.take(20)) {
        final String key = entry.key.toString();
        if (_blockedFieldKeyPattern.hasMatch(key)) {
          continue;
        }
        sanitized[_sanitizeText(key)] = _sanitizeValue(entry.value);
      }
      return sanitized;
    }
    return _sanitizeText(value.toString());
  }

  String _sanitizeText(String input) {
    var output = input;
    output = output.replaceAll(_urlPattern, '[url]');
    output = output.replaceAll(_emailPattern, '[email]');
    output = output.replaceAllMapped(_keyValueSecretPattern, (Match match) {
      return '${match.group(1)}=[redacted]';
    });
    output = output.replaceAll(_hexSecretPattern, '[redacted]');
    output = output.replaceAll(_longSecretPattern, '[redacted]');
    return output;
  }
}
