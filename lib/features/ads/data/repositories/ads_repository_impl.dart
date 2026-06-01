import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/features/ads/domain/entities/ads_entity.dart';
import 'package:Prism/features/ads/domain/repositories/ads_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: AdsRepository)
class AdsRepositoryImpl implements AdsRepository {
  static const ValidationFailure _adsDisabledFailure = ValidationFailure(
    'Ads are disabled in this Prism build',
  );

  AdsEntity _state = AdsEntity.empty;

  @override
  Future<Result<AdsEntity>> createRewardedAd() async {
    _state = AdsEntity.empty.copyWith(adFailed: true);
    return Result.success(_state);
  }

  @override
  Future<Result<AdsEntity>> showRewardedAd() async {
    _state = AdsEntity.empty.copyWith(adFailed: true);
    return Result.error(_adsDisabledFailure);
  }

  @override
  Future<Result<AdsEntity>> addReward({required num rewardAmount}) async {
    _state = AdsEntity.empty;
    return Result.success(_state);
  }

  @override
  Future<Result<AdsEntity>> reset() async {
    _state = AdsEntity.empty;
    return Result.success(_state);
  }
}
