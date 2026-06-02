import 'dart:io' show Platform;
import 'dart:ui';

import 'package:Prism/auth/apple_auth.dart';
import 'package:Prism/auth/google_auth.dart';
import 'package:Prism/core/audio/app_sound_manager.dart';
import 'package:Prism/core/di/injection.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/core/state/auth_runtime.dart';
import 'package:Prism/core/utils/edge_to_edge_overlay_style.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/env/env.dart';
import 'package:Prism/features/onboarding_v2/src/biz/onboarding_v2_bloc.j.dart';
import 'package:Prism/features/onboarding_v2/src/theme/onboarding_theme.dart';
import 'package:Prism/features/onboarding_v2/src/views/pages/f0_auth_page.dart';
import 'package:Prism/features/onboarding_v2/src/views/widgets/onboarding_background.dart';
import 'package:Prism/features/onboarding_v2/src/views/widgets/onboarding_copy.dart';
import 'package:Prism/features/onboarding_v2/src/views/widgets/onboarding_frame.dart';
import 'package:Prism/features/onboarding_v2/src/views/widgets/onboarding_primary_button.dart';
import 'package:Prism/features/onboarding_v2/src/views/widgets/onboarding_progress_indicator.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/toasts.dart' as toasts;
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:url_launcher/url_launcher.dart';

enum _AuthProvider { google, apple }

@RoutePage(name: 'OnboardingV2ShellRoute')
class OnboardingV2Shell extends StatefulWidget {
  const OnboardingV2Shell({super.key});

  @override
  State<OnboardingV2Shell> createState() => _OnboardingV2ShellState();
}

class _OnboardingV2ShellState extends State<OnboardingV2Shell> {
  late final OnboardingV2Bloc _bloc;
  late final TapGestureRecognizer _legalTap;
  bool _imagesPrecached = false;
  _AuthProvider? _loadingAuthProvider;

  static const List<Widget> _pages = [F0AuthPage()];

  static final _systemUiStyle = edgeToEdgeOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  @override
  void initState() {
    super.initState();
    _bloc = getIt<OnboardingV2Bloc>();
    _bloc.add(const OnboardingV2Event.started());
    AppSoundManager.instance.playEffect(AppSoundEffect.onboardingOpenSwoosh);
    _legalTap = TapGestureRecognizer()
      ..onTap = () => launchUrl(Uri.parse('https://prism-app-terms.web.app'), mode: LaunchMode.externalApplication);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      applyEdgeToEdgeOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagesPrecached) {
      _imagesPrecached = true;
      // wallpaperFinal reuses the same path as wallpaperPrimary, so one call covers both.
      precacheImage(const AssetImage(OnboardingAssets.wallpaperPrimary), context);
    }
  }

  @override
  void dispose() {
    _legalTap.dispose();
    _bloc.close();
    super.dispose();
  }

  Future<void> _handleNavRequest(BuildContext context, OnboardingV2NavRequest request) async {
    switch (request) {
      case OnboardingV2NavRequest.openPaywall:
      case OnboardingV2NavRequest.completeOnboarding:
        if (!context.mounted) return;
        context.router.replaceAll([const SplashWidgetRoute()]);
    }
  }

  Future<void> _handleAuthSignIn({
    required _AuthProvider provider,
    required Future<String> Function() signIn,
    required String cancelledResult,
  }) async {
    if (_loadingAuthProvider != null) {
      return;
    }
    setState(() => _loadingAuthProvider = provider);
    _bloc.add(const OnboardingV2Event.authLoadingChanged(isLoading: true));
    try {
      final String result = await signIn();
      if (!mounted) return;
      if (result == cancelledResult) {
        app_state.prismUser.loggedIn = false;
        await app_state.persistPrismUser();
        toasts.error('Sign in cancelled.');
        _bloc.add(const OnboardingV2Event.authLoadingChanged(isLoading: false));
      } else {
        app_state.prismUser.loggedIn = true;
        await app_state.persistPrismUser();
        _bloc.add(const OnboardingV2Event.authCompleted());
      }
    } catch (_) {
      if (mounted) toasts.error('Something went wrong, please try again!');
      _bloc.add(const OnboardingV2Event.authLoadingChanged(isLoading: false));
    } finally {
      if (mounted) {
        setState(() => _loadingAuthProvider = null);
      }
    }
  }

  Future<void> _handleGoogleSignIn() {
    return _handleAuthSignIn(
      provider: _AuthProvider.google,
      signIn: app_state.gAuth.signInWithGoogle,
      cancelledResult: GoogleAuth.signInCancelledResult,
    );
  }

  Future<void> _handleAppleSignIn() {
    return _handleAuthSignIn(
      provider: _AuthProvider.apple,
      signIn: globalAppleAuth.signInWithApple,
      cancelledResult: AppleAuth.signInCancelledResult,
    );
  }

  void _handleCtaTap(OnboardingV2Step step) {
    if (step == OnboardingV2Step.auth) {
      _handleGoogleSignIn();
      return;
    }
    _bloc.add(const OnboardingV2Event.authCompleted());
  }

  Widget _pageFor(OnboardingV2Step step) {
    final Widget page = _pages[0];
    return KeyedSubtree(key: ValueKey(step), child: page);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<OnboardingV2Bloc, OnboardingV2State>(
        listenWhen: (prev, curr) {
          final navChanged = curr.navRequest != null && prev.navRequest != curr.navRequest;
          return navChanged;
        },
        listener: (context, state) {
          logger.d('listener fired step=${state.step} navRequest=${state.navRequest}', tag: 'OnboardingV2Shell');
          if (state.navRequest != null) _handleNavRequest(context, state.navRequest!);
        },
        buildWhen: (prev, curr) =>
            prev.step != curr.step || prev.isAuthLoading != curr.isAuthLoading || prev.actionStatus != curr.actionStatus,
        builder: (context, state) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _systemUiStyle,
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                _bloc.add(const OnboardingV2Event.stepBack());
              },
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Layer 0: animated background (blur + image cross-fade).
                    // from page content and overlay layers. Verify background renders correctly.
                    RepaintBoundary(
                      child: OnboardingStepBackground(
                        step: state.step,
                        wallpaperUrl: state.wallpaperData.wallpaper?.fullUrl,
                      ),
                    ),

                    // Layer 1: unique page content — fades between steps.
                    AnimatedSwitcher(
                      duration: OnboardingMotion.normal,
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        children: [...previousChildren, if (currentChild != null) currentChild],
                      ),
                      child: _pageFor(state.step),
                    ),

                    // Layer 2: shared animated overlay (headline, progress, button, helper).
                    // repaints from the background and page layers. Verify overlay renders correctly.
                    RepaintBoundary(
                      child: _SharedOverlay(
                        state: state,
                        legalTap: _legalTap,
                        authProviderLoading: _loadingAuthProvider,
                        onCtaTap: () => _handleCtaTap(state.step),
                        onAppleTap: _handleAppleSignIn,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SharedOverlay — shared elements that hero across all 4 steps.
// Staggered fade-in fires once on initial mount (F0 open).
// ---------------------------------------------------------------------------
class _SharedOverlay extends StatefulWidget {
  const _SharedOverlay({
    required this.state,
    required this.legalTap,
    required this.authProviderLoading,
    required this.onCtaTap,
    required this.onAppleTap,
  });

  final OnboardingV2State state;
  final TapGestureRecognizer legalTap;
  final _AuthProvider? authProviderLoading;
  final VoidCallback onCtaTap;
  final VoidCallback onAppleTap;

  @override
  State<_SharedOverlay> createState() => _SharedOverlayState();
}

class _SharedOverlayState extends State<_SharedOverlay> {
  bool _headlineVisible = false;
  bool _buttonVisible = false;
  bool _bottomTextVisible = false;

  // Defaults to white so F3 is always legible before palette resolves.
  Color _wallpaperHeadlineColor = OnboardingColors.textOnDark;
  // Defaults to light icons (for dark wallpaper) before palette resolves.
  Brightness _statusBarIconBrightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        setState(() => _headlineVisible = true);
      });
      Future.delayed(const Duration(milliseconds: 750), () {
        if (!mounted) return;
        setState(() => _buttonVisible = true);
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() => _bottomTextVisible = true);
      });
    });
  }

  @override
  void didUpdateWidget(_SharedOverlay old) {
    super.didUpdateWidget(old);
    final oldUrl = old.state.wallpaperData.wallpaper?.thumbnailUrl;
    final newUrl = widget.state.wallpaperData.wallpaper?.thumbnailUrl;
    if (newUrl != null && newUrl.isNotEmpty && newUrl != oldUrl) {
      _computeWallpaperHeadlineColor(newUrl);
    }
  }

  Future<void> _computeWallpaperHeadlineColor(String thumbnailUrl) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(thumbnailUrl),
        maximumColorCount: 8,
      );
      final dominant = palette.dominantColor?.color ?? Colors.black;
      final brightness = ThemeData.estimateBrightnessForColor(dominant);
      if (mounted) {
        setState(() {
          _wallpaperHeadlineColor = brightness == Brightness.light
              ? OnboardingColors.textPrimary
              : OnboardingColors.textOnDark;
          _statusBarIconBrightness = brightness == Brightness.light ? Brightness.dark : Brightness.light;
        });
      }
    } catch (_) {
      // Keep current color on error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.state.step;
    final overlayStyle = step == OnboardingV2Step.firstWallpaper
        ? edgeToEdgeOverlayStyle(
            statusBarIconBrightness: _statusBarIconBrightness,
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : null;
    final content = OnboardingFrame(
      builder: (context, sx, sy) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _Progress(step: step, sx: sx, sy: sy, wallpaperColor: _wallpaperHeadlineColor),
            _Headline(step: step, sx: sx, sy: sy, visible: _headlineVisible, wallpaperColor: _wallpaperHeadlineColor),
            _ProBadge(step: step, sx: sx, sy: sy, visible: _headlineVisible, color: _wallpaperHeadlineColor),
            _CtaButton(
              step: step,
              sx: sx,
              sy: sy,
              visible: _buttonVisible,
              state: widget.state,
              authProviderLoading: widget.authProviderLoading,
              onCtaTap: widget.onCtaTap,
              onAppleTap: widget.onAppleTap,
            ),
            _BottomText(
              step: step,
              sx: sx,
              sy: sy,
              visible: _bottomTextVisible,
              legalTap: widget.legalTap,
              wallpaperCategory: widget.state.wallpaperData.wallpaper?.sourceCategory,
              aiGenerateStatus: widget.state.aiData.status,
            ),
          ],
        );
      },
    );
    return overlayStyle != null ? AnnotatedRegion<SystemUiOverlayStyle>(value: overlayStyle, child: content) : content;
  }
}

// ---------------------------------------------------------------------------
// Shared overlay sub-widgets — extracted from _build* methods so Flutter can
// skip rebuilding unchanged subtrees independently.
// ---------------------------------------------------------------------------

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.sx, required this.sy, required this.wallpaperColor});

  final OnboardingV2Step step;
  final double sx;
  final double sy;
  final Color wallpaperColor;

  @override
  Widget build(BuildContext context) {
    final visible =
        step == OnboardingV2Step.interests ||
        step == OnboardingV2Step.aiGenerate ||
        step == OnboardingV2Step.firstWallpaper;

    final progressStep = switch (step) {
      OnboardingV2Step.interests => 1,
      OnboardingV2Step.starterPack || OnboardingV2Step.aiGenerate => 2,
      _ => 3,
    };

    final color = step == OnboardingV2Step.firstWallpaper ? wallpaperColor : OnboardingColors.progressActive;

    return Positioned(
      top: OnboardingLayout.progressY * sy,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: OnboardingMotion.normal,
        opacity: visible ? 1.0 : 0.0,
        child: Center(
          child: Transform.scale(
            scaleX: sx,
            scaleY: sy,
            alignment: Alignment.topCenter,
            child: OnboardingProgressIndicator(step: progressStep, totalSteps: 3, color: color),
          ),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.step,
    required this.sx,
    required this.sy,
    required this.visible,
    required this.wallpaperColor,
  });

  final OnboardingV2Step step;
  final double sx;
  final double sy;
  final bool visible;

  /// Color used for the headline on the firstWallpaper step, derived from the wallpaper palette.
  final Color wallpaperColor;

  static double _headlineY(OnboardingV2Step step) =>
      step == OnboardingV2Step.auth ? OnboardingLayout.welcomeHeadlineY : OnboardingLayout.stepTitleY;

  static double _headlineX(OnboardingV2Step step) => switch (step) {
    // Auth: no horizontal constraint — the explicit \n is the only line break.
    // Applying padding here would squeeze "Your screen," onto a second line.
    OnboardingV2Step.auth => 0,
    OnboardingV2Step.interests => OnboardingLayout.step2TitleX,
    OnboardingV2Step.starterPack => OnboardingLayout.step4TitleX,
    OnboardingV2Step.aiGenerate => OnboardingLayout.step4TitleX,
    OnboardingV2Step.firstWallpaper => OnboardingLayout.step4TitleX,
  };

  static String _headlineText(OnboardingV2Step step) => switch (step) {
    OnboardingV2Step.auth => 'Your screen,\nreimagined.',
    OnboardingV2Step.interests => 'Pick your vibe',
    OnboardingV2Step.starterPack => 'Create your\nfirst wallpaper',
    OnboardingV2Step.aiGenerate => 'Create your\nfirst wallpaper',
    OnboardingV2Step.firstWallpaper => 'Make it yours',
  };

  @override
  Widget build(BuildContext context) {
    final text = _headlineText(step);
    final style = step == OnboardingV2Step.auth
        ? OnboardingTypography.headline.copyWith(fontSize: 32, height: 1.08)
        : step == OnboardingV2Step.firstWallpaper
        ? OnboardingTypography.headline.copyWith(color: wallpaperColor)
        : OnboardingTypography.headline;
    return AnimatedPositioned(
      duration: OnboardingMotion.normal,
      curve: OnboardingMotion.emphasized,
      top: _headlineY(step) * sy,
      left: _headlineX(step) * sx,
      right: _headlineX(step) * sx,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 1000),
        child: AnimatedSwitcher(
          duration: OnboardingMotion.short,
          child: Text(
            key: ValueKey(text),
            text,
            style: style,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.step,
    required this.sx,
    required this.sy,
    required this.visible,
    required this.state,
    required this.authProviderLoading,
    required this.onCtaTap,
    required this.onAppleTap,
  });

  final OnboardingV2Step step;
  final double sx;
  final double sy;
  final bool visible;
  final OnboardingV2State state;
  final _AuthProvider? authProviderLoading;
  final VoidCallback onCtaTap;
  final VoidCallback onAppleTap;

  @override
  Widget build(BuildContext context) {
    final isLoading = switch (step) {
      OnboardingV2Step.auth => state.isAuthLoading,
      OnboardingV2Step.interests => state.actionStatus == ActionStatus.inProgress,
      OnboardingV2Step.starterPack => state.aiData.status == AiGenerateStatus.loading,
      OnboardingV2Step.aiGenerate => state.aiData.status == AiGenerateStatus.loading,
      OnboardingV2Step.firstWallpaper => state.wallpaperData.status == FirstWallpaperStatus.loading,
    };

    final isEnabled = switch (step) {
      OnboardingV2Step.auth => true,
      OnboardingV2Step.interests => state.interestsData.canContinue,
      OnboardingV2Step.starterPack => true,
      OnboardingV2Step.aiGenerate => true,
      OnboardingV2Step.firstWallpaper => true,
    };

    if (step == OnboardingV2Step.auth) {
      final bool showApple = (Platform.isIOS || Platform.isMacOS) && !Env.sideloadBuild;
      final double buttonHeight = OnboardingLayout.authCtaHeight * sy;
      final double totalHeight = showApple
          ? (OnboardingLayout.authCtaHeight * 2 + OnboardingLayout.authCtaGap) * sy
          : buttonHeight;
      return Positioned(
        top: OnboardingLayout.authCtaY * sy,
        left: OnboardingLayout.ctaX * sx,
        right: OnboardingLayout.ctaX * sx,
        height: totalHeight,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 1000),
          child: _AuthButtons(
            showApple: showApple,
            buttonHeight: buttonHeight,
            gap: OnboardingLayout.authCtaGap * sy,
            enabled: isEnabled,
            loadingProvider: authProviderLoading,
            onGoogleTap: onCtaTap,
            onAppleTap: onAppleTap,
          ),
        ),
      );
    }

    final label = switch (step) {
      OnboardingV2Step.auth => 'continue with Google',
      OnboardingV2Step.interests => 'continue',
      OnboardingV2Step.starterPack => 'continue',
      OnboardingV2Step.aiGenerate => 'continue',
      OnboardingV2Step.firstWallpaper => 'set as wallpaper',
    };

    return Positioned(
      top: OnboardingLayout.ctaY * sy,
      left: OnboardingLayout.ctaX * sx,
      right: OnboardingLayout.ctaX * sx,
      height: OnboardingLayout.ctaHeight * sy,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 1000),
        child: OnboardingPrimaryButton(label: label, onPressed: onCtaTap, enabled: isEnabled, loading: isLoading),
      ),
    );
  }
}


class _AuthButtons extends StatelessWidget {
  const _AuthButtons({
    required this.showApple,
    required this.buttonHeight,
    required this.gap,
    required this.enabled,
    required this.loadingProvider,
    required this.onGoogleTap,
    required this.onAppleTap,
  });

  final bool showApple;
  final double buttonHeight;
  final double gap;
  final bool enabled;
  final _AuthProvider? loadingProvider;
  final VoidCallback onGoogleTap;
  final VoidCallback onAppleTap;

  @override
  Widget build(BuildContext context) {
    final bool anyLoading = loadingProvider != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: buttonHeight,
          child: OnboardingPrimaryButton(
            label: 'Continue with Google',
            onPressed: onGoogleTap,
            enabled: enabled && !anyLoading,
            loading: loadingProvider == _AuthProvider.google,
          ),
        ),
        if (showApple) ...[
          SizedBox(height: gap),
          SizedBox(
            height: buttonHeight,
            child: _AppleSignInButton(
              onPressed: onAppleTap,
              enabled: enabled && !anyLoading,
              loading: loadingProvider == _AuthProvider.apple,
            ),
          ),
        ],
      ],
    );
  }
}

class _AppleSignInButton extends StatelessWidget {
  const _AppleSignInButton({required this.onPressed, required this.enabled, required this.loading});

  final VoidCallback onPressed;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = enabled && !loading;
    return AnimatedOpacity(
      duration: OnboardingMotion.short,
      opacity: isEnabled || loading ? 1 : OnboardingOpacity.disabledButton,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(OnboardingRadius.cta),
        child: InkWell(
          borderRadius: BorderRadius.circular(OnboardingRadius.cta),
          onTap: isEnabled ? onPressed : null,
          child: Center(
            child: AnimatedSwitcher(
              duration: OnboardingMotion.short,
              child: loading
                  ? const SizedBox(
                      width: OnboardingLayout.loadingIndicatorSize,
                      height: OnboardingLayout.loadingIndicatorSize,
                      child: CircularProgressIndicator(
                        strokeWidth: OnboardingLayout.loadingIndicatorStroke,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.apple, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text('Continue with Apple', style: OnboardingTypography.cta.copyWith(color: Colors.white)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomText extends StatelessWidget {
  const _BottomText({
    required this.step,
    required this.sx,
    required this.sy,
    required this.visible,
    required this.legalTap,
    this.wallpaperCategory,
    this.aiGenerateStatus,
  });

  final OnboardingV2Step step;
  final double sx;
  final double sy;
  final bool visible;
  final TapGestureRecognizer legalTap;
  final String? wallpaperCategory;
  final AiGenerateStatus? aiGenerateStatus;

  String _helperText() => switch (step) {
    OnboardingV2Step.interests => 'select at least 3 categories to personalize your feed',
    OnboardingV2Step.starterPack => 'your first wallpaper',
    OnboardingV2Step.aiGenerate => switch (aiGenerateStatus) {
      AiGenerateStatus.success => 'looking good! tap "use this wallpaper" to continue',
      AiGenerateStatus.failure => 'something went wrong — tap generate to try again',
      _ => 'your first wallpaper',
    },
    _ =>
      (wallpaperCategory != null && wallpaperCategory!.isNotEmpty)
          ? 'we picked this wallpaper based on your interest in $wallpaperCategory'
          : 'we picked this wallpaper just for you',
  };

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (step == OnboardingV2Step.auth) {
      content = RichText(
        key: const ValueKey('legal'),
        textAlign: TextAlign.center,
        text: TextSpan(
          style: OnboardingTypography.helper,
          children: [
            const TextSpan(text: 'by continuing you agree to our '),
            TextSpan(
              text: 'Terms & Conditions',
              style: OnboardingTypography.helper.copyWith(decoration: TextDecoration.underline),
              recognizer: legalTap,
            ),
          ],
        ),
      );
    } else {
      final text = _helperText();
      content = OnboardingHelperText(key: ValueKey(text), text: text);
    }

    return AnimatedPositioned(
      duration: OnboardingMotion.normal,
      curve: OnboardingMotion.emphasized,
      top: OnboardingLayout.helperY * sy,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 1000),
        child: AnimatedSwitcher(duration: OnboardingMotion.short, child: content),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge({required this.step, required this.sx, required this.sy, required this.visible, required this.color});

  final OnboardingV2Step step;
  final double sx;
  final double sy;
  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: OnboardingLayout.step4BadgeY * sy,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (visible && step == OnboardingV2Step.firstWallpaper) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 1000),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: OnboardingLayout.softenedBlurSigma,
                sigmaY: OnboardingLayout.softenedBlurSigma,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: OnboardingTypography.sans,
                      fontSize: 12,
                      height: 1.2,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                    children: const [TextSpan(text: 'Prism catalog')],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
