import 'package:Prism/core/utils/result.dart';

/// Submits UGC reports when a remote reporting backend is available.
abstract class ContentReportRepository {
  /// [contentType] is `wall` or `setup` (server-enforced).
  Future<Result<void>> submitReport({
    required String contentType,
    required String targetRemoteStoreDocId,
    required String reason,
    String details = '',
    String appVersion = '',
  });
}
