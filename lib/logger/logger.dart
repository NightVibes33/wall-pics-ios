import 'package:Prism/core/debug/document_log_sink.dart';
import 'package:Prism/core/debug/in_memory_log_sink.dart';
import 'package:Prism/core/monitoring/sentry_log_sink.dart';
import 'package:Prism/logger/app_logger.dart';
import 'package:Prism/logger/log_sink.dart';

final AppLogger logger = AppLogger(
  minimumLevel: AppLogLevel.trace,
  sink: CompositeLogSink(<LogSink>[
    PrintLogSink(),
    DocumentLogSink.instance,
    SentryLogSink(),
    InMemoryLogSink.instance,
  ]),
);

const String logExportDisabledMarker = 'DISABLED::::';

Future<String> zipLogs() {
  return DocumentLogSink.instance.flushAndGetPath();
}
