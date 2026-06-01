import 'package:Prism/core/content_reports/content_report_repository.dart';
import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ContentReportRepository)
class LocalContentReportRepository implements ContentReportRepository {
  const LocalContentReportRepository();

  @override
  Future<Result<void>> submitReport({
    required String contentType,
    required String targetRemoteStoreDocId,
    required String reason,
    String details = '',
    String appVersion = '',
  }) async {
    return Result.error(const ServerFailure('Content reports are unavailable in this build.'));
  }
}
