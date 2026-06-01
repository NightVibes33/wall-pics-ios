import 'dart:io';

import 'package:Prism/core/analytics/events/analytics_enums.dart';
import 'package:Prism/core/router/not_found_page.dart';
import 'package:Prism/core/router/route_guards.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/features/admin_review/views/pages/remote_store_telemetry_screen.dart';
import 'package:Prism/features/category_feed/views/pages/collection_view_screen.dart';
import 'package:Prism/features/debug_panel/views/pages/debug_panel_page.dart';
import 'package:Prism/features/favourite_walls/views/pages/favourite_wall_screen.dart';
import 'package:Prism/features/navigation/views/pages/collection_tab_page.dart';
import 'package:Prism/features/navigation/views/pages/dashboard_page.dart';
import 'package:Prism/features/navigation/views/pages/home_tab_page.dart';
import 'package:Prism/features/navigation/views/pages/search_tab_page.dart';
import 'package:Prism/features/onboarding_v2/src/views/onboarding_v2_shell.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';
import 'package:Prism/features/palette/views/pages/download_screen.dart';
import 'package:Prism/features/palette/views/pages/download_wallpaper_screen.dart';
import 'package:Prism/features/palette/views/pages/wallpaper_detail_screen.dart';
import 'package:Prism/features/palette/views/pages/wallpaper_filter_screen.dart';
import 'package:Prism/features/quick_tiles/views/quick_tile_settings_screen.dart';
import 'package:Prism/features/session/views/pages/about_screen.dart';
import 'package:Prism/features/session/views/pages/settings_screen.dart';
import 'package:Prism/features/startup/views/pages/splash_widget.dart';
import 'package:Prism/features/theme_mode/views/pages/theme_view_page.dart';
import 'package:Prism/features/user_search/views/pages/search_screen.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' show Image;

part 'app_router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  AppRouter({super.navigatorKey});

  final SignedInGuard _signedInGuard = const SignedInGuard();
  final AdminGuard _adminGuard = const AdminGuard();

  @override
  List<AutoRoute> get routes => [
    // Startup
    AutoRoute(path: '/', page: SplashWidgetRoute.page),
    AutoRoute(path: '/onboarding/v2', page: OnboardingV2ShellRoute.page),

    // Dashboard shell with bottom nav tabs
    AutoRoute(
      path: '/dashboard',
      page: DashboardRoute.page,
      guards: [_signedInGuard],
      children: [
        // Home tab
        AutoRoute(path: 'home', page: HomeTabRoute.page),
        // Search tab
        AutoRoute(path: 'search', page: SearchTabRoute.page, children: [AutoRoute(path: '', page: SearchRoute.page)]),
        // Categories tab
        AutoRoute(path: 'collection', page: CollectionTabRoute.page),
      ],
    ),

    // Global routes (pushed over entire shell as full-screen dialogs)
    AutoRoute(path: '/wallpaper-detail', page: WallpaperDetailRoute.page),
    RedirectRoute(path: '/share', redirectTo: '/wallpaper-detail'), // Replaces ShareWallpaperViewRoute
    AutoRoute(path: '/download-wallpaper', page: DownloadWallpaperRoute.page),
    AutoRoute(path: '/wallpaper-filter', page: WallpaperFilterRoute.page),
    AutoRoute(path: '/settings', page: SettingsRoute.page),
    AutoRoute(path: '/about', page: AboutRoute.page),
    AutoRoute(path: '/fav-walls', page: FavouriteWallpaperRoute.page),
    AutoRoute(path: '/downloads', page: DownloadRoute.page),
    AutoRoute(path: '/theme', page: ThemeViewRoute.page),
    AutoRoute(path: '/collection-view', page: CollectionViewRoute.page),
    AutoRoute(path: '/admin-remote-store-telemetry', page: RemoteStoreTelemetryRoute.page, guards: [_adminGuard]),
    AutoRoute(path: '/debug-panel', page: DebugPanelRoute.page, guards: [_adminGuard]),
    AutoRoute(path: '/quick-tile-settings', page: QuickTileSettingsRoute.page),
    AutoRoute(path: '/not-found', page: NotFoundRoute.page),
    RedirectRoute(path: '*', redirectTo: '/not-found'),
  ];
}
