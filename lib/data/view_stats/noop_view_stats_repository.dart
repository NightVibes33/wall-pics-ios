import 'package:Prism/core/utils/result.dart';
import 'package:Prism/core/view_stats/view_stats_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ViewStatsRepository)
class NoopViewStatsRepository implements ViewStatsRepository {
  const NoopViewStatsRepository();

  @override
  Future<Result<String>> recordWallpaperView(String wallId) async => Result.success('0');

  @override
  Future<Result<String>> recordSetupView(String setupId) async => Result.success('0');
}
