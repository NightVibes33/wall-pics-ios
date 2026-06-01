// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [AboutScreen]
class AboutRoute extends PageRouteInfo<void> {
  const AboutRoute({List<PageRouteInfo>? children})
    : super(AboutRoute.name, initialChildren: children);

  static const String name = 'AboutRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AboutScreen();
    },
  );
}

/// generated route for
/// [CollectionTabPage]
class CollectionTabRoute extends PageRouteInfo<void> {
  const CollectionTabRoute({List<PageRouteInfo>? children})
    : super(CollectionTabRoute.name, initialChildren: children);

  static const String name = 'CollectionTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const CollectionTabPage();
    },
  );
}

/// generated route for
/// [CollectionViewScreen]
class CollectionViewRoute extends PageRouteInfo<CollectionViewRouteArgs> {
  CollectionViewRoute({
    Key? key,
    required String collectionName,
    List<PageRouteInfo>? children,
  }) : super(
         CollectionViewRoute.name,
         args: CollectionViewRouteArgs(
           key: key,
           collectionName: collectionName,
         ),
         initialChildren: children,
       );

  static const String name = 'CollectionViewRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<CollectionViewRouteArgs>();
      return CollectionViewScreen(
        key: args.key,
        collectionName: args.collectionName,
      );
    },
  );
}

class CollectionViewRouteArgs {
  const CollectionViewRouteArgs({this.key, required this.collectionName});

  final Key? key;

  final String collectionName;

  @override
  String toString() {
    return 'CollectionViewRouteArgs{key: $key, collectionName: $collectionName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollectionViewRouteArgs) return false;
    return key == other.key && collectionName == other.collectionName;
  }

  @override
  int get hashCode => key.hashCode ^ collectionName.hashCode;
}

/// generated route for
/// [DashboardPage]
class DashboardRoute extends PageRouteInfo<void> {
  const DashboardRoute({List<PageRouteInfo>? children})
    : super(DashboardRoute.name, initialChildren: children);

  static const String name = 'DashboardRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DashboardPage();
    },
  );
}

/// generated route for
/// [DebugPanelPage]
class DebugPanelRoute extends PageRouteInfo<void> {
  const DebugPanelRoute({List<PageRouteInfo>? children})
    : super(DebugPanelRoute.name, initialChildren: children);

  static const String name = 'DebugPanelRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DebugPanelPage();
    },
  );
}

/// generated route for
/// [DownloadScreen]
class DownloadRoute extends PageRouteInfo<void> {
  const DownloadRoute({List<PageRouteInfo>? children})
    : super(DownloadRoute.name, initialChildren: children);

  static const String name = 'DownloadRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return DownloadScreen();
    },
  );
}

/// generated route for
/// [DownloadWallpaperScreen]
class DownloadWallpaperRoute extends PageRouteInfo<DownloadWallpaperRouteArgs> {
  DownloadWallpaperRoute({
    Key? key,
    required WallpaperSource source,
    required File file,
    List<PageRouteInfo>? children,
  }) : super(
         DownloadWallpaperRoute.name,
         args: DownloadWallpaperRouteArgs(key: key, source: source, file: file),
         initialChildren: children,
       );

  static const String name = 'DownloadWallpaperRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DownloadWallpaperRouteArgs>();
      return DownloadWallpaperScreen(
        key: args.key,
        source: args.source,
        file: args.file,
      );
    },
  );
}

class DownloadWallpaperRouteArgs {
  const DownloadWallpaperRouteArgs({
    this.key,
    required this.source,
    required this.file,
  });

  final Key? key;

  final WallpaperSource source;

  final File file;

  @override
  String toString() {
    return 'DownloadWallpaperRouteArgs{key: $key, source: $source, file: $file}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DownloadWallpaperRouteArgs) return false;
    return key == other.key && source == other.source && file == other.file;
  }

  @override
  int get hashCode => key.hashCode ^ source.hashCode ^ file.hashCode;
}

/// generated route for
/// [FavouriteWallpaperScreen]
class FavouriteWallpaperRoute extends PageRouteInfo<void> {
  const FavouriteWallpaperRoute({List<PageRouteInfo>? children})
    : super(FavouriteWallpaperRoute.name, initialChildren: children);

  static const String name = 'FavouriteWallpaperRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FavouriteWallpaperScreen();
    },
  );
}

/// generated route for
/// [RemoteStoreTelemetryScreen]
class RemoteStoreTelemetryRoute extends PageRouteInfo<void> {
  const RemoteStoreTelemetryRoute({List<PageRouteInfo>? children})
    : super(RemoteStoreTelemetryRoute.name, initialChildren: children);

  static const String name = 'RemoteStoreTelemetryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const RemoteStoreTelemetryScreen();
    },
  );
}

/// generated route for
/// [HomeTabPage]
class HomeTabRoute extends PageRouteInfo<void> {
  const HomeTabRoute({List<PageRouteInfo>? children})
    : super(HomeTabRoute.name, initialChildren: children);

  static const String name = 'HomeTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const HomeTabPage();
    },
  );
}

/// generated route for
/// [NotFoundPage]
class NotFoundRoute extends PageRouteInfo<void> {
  const NotFoundRoute({List<PageRouteInfo>? children})
    : super(NotFoundRoute.name, initialChildren: children);

  static const String name = 'NotFoundRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const NotFoundPage();
    },
  );
}

/// generated route for
/// [OnboardingV2Shell]
class OnboardingV2ShellRoute extends PageRouteInfo<void> {
  const OnboardingV2ShellRoute({List<PageRouteInfo>? children})
    : super(OnboardingV2ShellRoute.name, initialChildren: children);

  static const String name = 'OnboardingV2ShellRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const OnboardingV2Shell();
    },
  );
}

/// generated route for
/// [QuickTileSettingsScreen]
class QuickTileSettingsRoute extends PageRouteInfo<void> {
  const QuickTileSettingsRoute({List<PageRouteInfo>? children})
    : super(QuickTileSettingsRoute.name, initialChildren: children);

  static const String name = 'QuickTileSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const QuickTileSettingsScreen();
    },
  );
}

/// generated route for
/// [SearchScreen]
class SearchRoute extends PageRouteInfo<void> {
  const SearchRoute({List<PageRouteInfo>? children})
    : super(SearchRoute.name, initialChildren: children);

  static const String name = 'SearchRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return SearchScreen();
    },
  );
}

/// generated route for
/// [SearchTabPage]
class SearchTabRoute extends PageRouteInfo<void> {
  const SearchTabRoute({List<PageRouteInfo>? children})
    : super(SearchTabRoute.name, initialChildren: children);

  static const String name = 'SearchTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SearchTabPage();
    },
  );
}

/// generated route for
/// [SettingsScreen]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsScreen();
    },
  );
}

/// generated route for
/// [SplashWidget]
class SplashWidgetRoute extends PageRouteInfo<void> {
  const SplashWidgetRoute({List<PageRouteInfo>? children})
    : super(SplashWidgetRoute.name, initialChildren: children);

  static const String name = 'SplashWidgetRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SplashWidget();
    },
  );
}

/// generated route for
/// [ThemeView]
class ThemeViewRoute extends PageRouteInfo<void> {
  const ThemeViewRoute({List<PageRouteInfo>? children})
    : super(ThemeViewRoute.name, initialChildren: children);

  static const String name = 'ThemeViewRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return ThemeView();
    },
  );
}

/// generated route for
/// [WallpaperDetailScreen]
class WallpaperDetailRoute extends PageRouteInfo<WallpaperDetailRouteArgs> {
  WallpaperDetailRoute({
    Key? key,
    WallpaperDetailEntity? entity,
    String? wallId,
    WallpaperSource? source,
    String? wallpaperUrl,
    String? thumbnailUrl,
    AnalyticsSurfaceValue analyticsSurface =
        AnalyticsSurfaceValue.wallpaperScreen,
    List<PageRouteInfo>? children,
  }) : super(
         WallpaperDetailRoute.name,
         args: WallpaperDetailRouteArgs(
           key: key,
           entity: entity,
           wallId: wallId,
           source: source,
           wallpaperUrl: wallpaperUrl,
           thumbnailUrl: thumbnailUrl,
           analyticsSurface: analyticsSurface,
         ),
         initialChildren: children,
       );

  static const String name = 'WallpaperDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<WallpaperDetailRouteArgs>(
        orElse: () => const WallpaperDetailRouteArgs(),
      );
      return WallpaperDetailScreen(
        key: args.key,
        entity: args.entity,
        wallId: args.wallId,
        source: args.source,
        wallpaperUrl: args.wallpaperUrl,
        thumbnailUrl: args.thumbnailUrl,
        analyticsSurface: args.analyticsSurface,
      );
    },
  );
}

class WallpaperDetailRouteArgs {
  const WallpaperDetailRouteArgs({
    this.key,
    this.entity,
    this.wallId,
    this.source,
    this.wallpaperUrl,
    this.thumbnailUrl,
    this.analyticsSurface = AnalyticsSurfaceValue.wallpaperScreen,
  });

  final Key? key;

  final WallpaperDetailEntity? entity;

  final String? wallId;

  final WallpaperSource? source;

  final String? wallpaperUrl;

  final String? thumbnailUrl;

  final AnalyticsSurfaceValue analyticsSurface;

  @override
  String toString() {
    return 'WallpaperDetailRouteArgs{key: $key, entity: $entity, wallId: $wallId, source: $source, wallpaperUrl: $wallpaperUrl, thumbnailUrl: $thumbnailUrl, analyticsSurface: $analyticsSurface}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WallpaperDetailRouteArgs) return false;
    return key == other.key &&
        entity == other.entity &&
        wallId == other.wallId &&
        source == other.source &&
        wallpaperUrl == other.wallpaperUrl &&
        thumbnailUrl == other.thumbnailUrl &&
        analyticsSurface == other.analyticsSurface;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      entity.hashCode ^
      wallId.hashCode ^
      source.hashCode ^
      wallpaperUrl.hashCode ^
      thumbnailUrl.hashCode ^
      analyticsSurface.hashCode;
}

/// generated route for
/// [WallpaperFilterScreen]
class WallpaperFilterRoute extends PageRouteInfo<WallpaperFilterRouteArgs> {
  WallpaperFilterRoute({
    Key? key,
    Image? image,
    Image? finalImage,
    String? filename,
    String? finalFilename,
    List<PageRouteInfo>? children,
  }) : super(
         WallpaperFilterRoute.name,
         args: WallpaperFilterRouteArgs(
           key: key,
           image: image,
           finalImage: finalImage,
           filename: filename,
           finalFilename: finalFilename,
         ),
         initialChildren: children,
       );

  static const String name = 'WallpaperFilterRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<WallpaperFilterRouteArgs>(
        orElse: () => const WallpaperFilterRouteArgs(),
      );
      return WallpaperFilterScreen(
        key: args.key,
        image: args.image,
        finalImage: args.finalImage,
        filename: args.filename,
        finalFilename: args.finalFilename,
      );
    },
  );
}

class WallpaperFilterRouteArgs {
  const WallpaperFilterRouteArgs({
    this.key,
    this.image,
    this.finalImage,
    this.filename,
    this.finalFilename,
  });

  final Key? key;

  final Image? image;

  final Image? finalImage;

  final String? filename;

  final String? finalFilename;

  @override
  String toString() {
    return 'WallpaperFilterRouteArgs{key: $key, image: $image, finalImage: $finalImage, filename: $filename, finalFilename: $finalFilename}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WallpaperFilterRouteArgs) return false;
    return key == other.key &&
        image == other.image &&
        finalImage == other.finalImage &&
        filename == other.filename &&
        finalFilename == other.finalFilename;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      image.hashCode ^
      finalImage.hashCode ^
      filename.hashCode ^
      finalFilename.hashCode;
}
