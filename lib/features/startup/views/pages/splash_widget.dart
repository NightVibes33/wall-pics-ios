import 'dart:async';

import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/core/state/auth_runtime.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/features/onboarding_v2/src/utils/onboarding_v2_config.dart';
import 'package:Prism/features/startup/biz/bloc/startup_bloc.j.dart';
import 'package:Prism/features/startup/views/pages/old_version_screen.dart';
import 'package:Prism/logger/logger.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage(name: 'SplashWidgetRoute')
class SplashWidget extends StatefulWidget {
  const SplashWidget({super.key});

  @override
  State<SplashWidget> createState() => _SplashWidgetState();
}

class _SplashWidgetState extends State<SplashWidget> {
  final SettingsLocalDataSource _settingsLocal = getIt<SettingsLocalDataSource>();
  bool _navigated = false;
  bool _notchMeasured = false;
  Timer? _failOpenTimer;

  // Tracks whether the debug-forced onboarding redirect has already fired this
  // app session. Resets on process restart (static lives for the process lifetime).
  static bool _debugOnboardingShownThisSession = false;

  @override
  void initState() {
    super.initState();
    // If startup already succeeded (e.g. returning from onboarding), the
    // BlocConsumer listener won't fire because there's no state change.
    // Schedule an immediate check so navigation still happens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<StartupBloc>().state;
      if (s.status == LoadStatus.success && !s.isObsoleteVersion) {
        unawaited(_navigatePostBootstrap(context));
      }
    });
    _failOpenTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _navigated) {
        return;
      }
      logger.w('Startup bootstrap timed out; continuing to auth flow.', tag: 'Startup');
      unawaited(_navigatePostBootstrap(context));
    });
  }

  void _measureNotch(BuildContext context) {
    if (_notchMeasured) {
      return;
    }
    final height = MediaQuery.of(context).padding.top;
    app_state.hasNotch = height > 24;
    app_state.notchSize = height;
    context.read<StartupBloc>().add(StartupEvent.notchMeasured(notchHeight: height));
    _notchMeasured = true;
    logger.d('Notch Height = $height');
  }

  Future<void> _navigatePostBootstrap(BuildContext context) async {
    if (_navigated) {
      return;
    }
    _navigated = true;
    await waitForAuthBootstrap();
    if (!mounted) {
      return;
    }
    final effectiveDebugForce = OnboardingV2Config.debugForceOnboarding && !_debugOnboardingShownThisSession;
    final isOnboarded = !effectiveDebugForce && _settingsLocal.get<bool>('onboarded_v2_new', defaultValue: false);
    final v2Enabled = effectiveDebugForce || (context.read<StartupBloc>().state.config?.onboardingV2Enabled ?? false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final isLoggedIn = app_state.prismUser.loggedIn;
      final routes = !isLoggedIn || (!isOnboarded && v2Enabled)
          ? <PageRouteInfo>[const OnboardingV2ShellRoute()]
          : <PageRouteInfo>[const DashboardRoute()];
      final targetRoute = routes.first is OnboardingV2ShellRoute ? 'onboarding' : 'dashboard';
      logger.i(
        'Startup route resolved.',
        tag: 'Startup',
        fields: <String, Object?>{
          'logged_in': isLoggedIn,
          'onboarded': isOnboarded,
          'onboarding_v2': v2Enabled,
          'target': targetRoute,
        },
      );
      if (routes.first is OnboardingV2ShellRoute) {
        _debugOnboardingShownThisSession = true;
      }
      try {
        context.router.replaceAll(routes);
      } catch (error, stackTrace) {
        _navigated = false;
        logger.e('Post-bootstrap navigation failed.', tag: 'Startup', error: error, stackTrace: stackTrace);
      }
    });
  }

  @override
  void dispose() {
    _failOpenTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measureNotch(context);

    return BlocConsumer<StartupBloc, StartupState>(
      listener: (context, state) {
        if (state.status == LoadStatus.success && !state.isObsoleteVersion) {
          unawaited(_navigatePostBootstrap(context));
        } else if (state.status == LoadStatus.failure) {
          logger.w(
            'Startup bootstrap failed; continuing to auth flow.',
            tag: 'Startup',
            error: state.failure,
          );
          unawaited(_navigatePostBootstrap(context));
        }
      },
      builder: (context, state) {
        if (state.status == LoadStatus.success && state.isObsoleteVersion) {
          return OldVersion();
        }
        return const _SecondarySplash();
      },
    );
  }
}

class _SecondarySplash extends StatelessWidget {
  const _SecondarySplash();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      color: Colors.black,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.29074074074,
          height: MediaQuery.of(context).size.width * 0.29074074074,
          decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage('assets/images/ic_launcher.webp'), fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
