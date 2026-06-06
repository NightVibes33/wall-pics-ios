import 'dart:async';

import 'package:Prism/core/constants/app_constants.dart';
import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/data/categories/categories.dart' as category_data;
import 'package:Prism/data/notifications/notifications.dart';
import 'package:Prism/env/env.dart';
import 'package:Prism/features/in_app_notifications/biz/bloc/in_app_notifications_bloc.j.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/features/startup/domain/entities/startup_config_entity.dart';
import 'package:Prism/features/startup/domain/repositories/startup_repository.dart';
import 'package:Prism/logger/logger.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: StartupRepository)
class StartupRepositoryImpl implements StartupRepository {
  StartupRepositoryImpl(this._settingsLocal);

  final SettingsLocalDataSource _settingsLocal;
  final StreamController<StartupConfigEntity> _configController = StreamController<StartupConfigEntity>.broadcast();

  StartupConfigEntity? _currentConfig;

  @override
  StartupConfigEntity? get currentConfig => _currentConfig;

  @override
  Stream<StartupConfigEntity> watchConfig() async* {
    if (_currentConfig != null) {
      yield _currentConfig!;
    }
    yield* _configController.stream;
  }

  @override
  Future<Result<StartupConfigEntity>> bootstrap() async {
    try {
      logger.i('Using bundled startup configuration.', tag: 'StartupRepository');
      final topImageLink = defaultTopImageLink;
      final bannerText = defaultBannerText;
      final bannerTextOn = defaultBannerTextOn;
      final bannerUrl = defaultBannerUrl;
      final obsoleteVersion = defaultObsoleteAppVersion;
      final verifiedUsers = List<String>.from(defaultVerifiedUsers);
      final premiumCollections = List<String>.from(defaultPremiumCollections);
      final topTitleText = List<String>.from(defaultTopTitleText);
      final aiEnabled = defaultAiEnabled;
      final aiRolloutPercent = defaultAiRolloutPercent.clamp(0, 100);
      final aiSubmitEnabled = defaultAiSubmitEnabled;
      final aiVariationsEnabled = defaultAiVariationsEnabled;
      topTitleText.shuffle();
      final categories = category_data.categoryDefinitions
          .map(
            (def) => <String, dynamic>{
              'name': def.name,
              'source': def.source.name,
              'searchType': def.searchType.name,
              'imageUrl': def.imageUrl,
              'secondaryImageUrl': def.secondaryImageUrl,
              'catalogSlug': def.catalogSlug,
              'catalogContentType': def.catalogContentType,
            },
          )
          .toList(growable: false);

      final followersTab = _settingsLocal.get<bool>('followersTab', defaultValue: true);
      final onboardingV2Enabled = defaultOnboardingV2Enabled;
      final onboardingStarterPack = List<Map<String, dynamic>>.from(defaultOnboardingStarterPack);

      final entity = StartupConfigEntity(
        topImageLink: topImageLink,
        bannerText: bannerText,
        bannerTextOn: bannerTextOn,
        bannerUrl: bannerUrl,
        obsoleteAppVersion: obsoleteVersion,
        verifiedUsers: verifiedUsers,
        premiumCollections: premiumCollections,
        topTitleText: topTitleText,
        categories: categories,
        followersTab: followersTab,
        aiEnabled: aiEnabled,
        aiRolloutPercent: aiRolloutPercent,
        aiSubmitEnabled: aiSubmitEnabled,
        aiVariationsEnabled: aiVariationsEnabled,
        onboardingV2Enabled: onboardingV2Enabled,
        onboardingStarterPack: onboardingStarterPack,
      );

      _currentConfig = entity;
      if (!_configController.isClosed) {
        _configController.add(entity);
      }

      if (Env.sideloadBuild) {
        logger.i('Skipping optional startup repository warmups for sideload build.', tag: 'StartupRepository');
        return Result.success(entity);
      }

      unawaited(syncInAppNotificationsFromRemote());
      unawaited(PrismCatalogDataSource.instance.warmCatalogCache(prefetchMedia: false));
      if (getIt.isRegistered<InAppNotificationsBloc>()) {
        getIt<InAppNotificationsBloc>().add(const InAppNotificationsEvent.localReloadRequested());
      }

      return Result.success(entity);
    } catch (error) {
      return Result.error(ServerFailure('Startup bootstrap failed: $error'));
    }
  }
}
