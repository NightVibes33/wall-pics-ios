import 'dart:math' as math;
import 'dart:ui';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/logger/logger.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

class PrismBottomNav extends StatefulWidget {
  const PrismBottomNav({super.key});

  @override
  State<PrismBottomNav> createState() => _PrismBottomNavState();
}

class _PrismBottomNavState extends State<PrismBottomNav> {
  static const List<_NavTabConfig> _tabs = <_NavTabConfig>[
    _NavTabConfig(routeIndex: 0, label: 'Home', icon: JamIcons.home_f, value: NavTabValue.home),
    _NavTabConfig(routeIndex: 1, label: 'Live', icon: JamIcons.play_circle_f, value: NavTabValue.search),
    _NavTabConfig(routeIndex: 2, label: 'Widgets', icon: JamIcons.grid_f, value: NavTabValue.collection),
    _NavTabConfig(routeIndex: null, label: 'Profile', icon: JamIcons.user, value: null),
  ];

  TabsRouter? _tabsRouter;

  void _onRouterChange() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = AutoTabsRouter.of(context);
    if (router != _tabsRouter) {
      _tabsRouter?.removeListener(_onRouterChange);
      _tabsRouter = router;
      _tabsRouter!.addListener(_onRouterChange);
    }
  }

  @override
  void dispose() {
    _tabsRouter?.removeListener(_onRouterChange);
    super.dispose();
  }

  _NavTabConfig? _tabForRouteIndex(int routeIndex) {
    for (final tab in _tabs) {
      if (tab.routeIndex == routeIndex) {
        return tab;
      }
    }
    return null;
  }

  void _trackTabSelection({required int fromRouteIndex, required _NavTabConfig toTab}) {
    final fromTab = _tabForRouteIndex(fromRouteIndex);
    if (fromTab?.value == null || toTab.value == null) {
      return;
    }
    analytics.track(NavTabSelectedEvent(fromTab: fromTab!.value!, toTab: toTab.value!));
  }

  void _switchTab(_NavTabConfig tab) {
    final routeIndex = tab.routeIndex;
    if (routeIndex == null) {
      context.router.root.push(const SettingsRoute());
      return;
    }

    final fromIndex = _tabsRouter!.activeIndex;
    if (fromIndex == routeIndex) {
      logger.d('Currently on ${tab.label}');
      return;
    }
    _trackTabSelection(fromRouteIndex: fromIndex, toTab: tab);
    _tabsRouter!.setActiveIndex(routeIndex);
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _tabsRouter?.activeIndex ?? 0;
    final width = math.min(MediaQuery.sizeOf(context).width - 36, 430.0);

    return SizedBox(
      width: width,
      height: 78,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF242424).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 9)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: <Widget>[
                  for (final tab in _tabs)
                    Expanded(
                      child: _TabButton(
                        label: tab.label,
                        tooltip: tab.label,
                        isActive: activeIndex == tab.routeIndex,
                        icon: tab.icon,
                        onPressed: () => _switchTab(tab),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool isActive;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = Colors.white.withValues(alpha: isActive ? 1 : 0.9);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: double.infinity,
            decoration: BoxDecoration(
              color: isActive ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: foreground, size: 29),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground, fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTabConfig {
  const _NavTabConfig({required this.routeIndex, required this.label, required this.icon, required this.value});

  final int? routeIndex;
  final String label;
  final IconData icon;
  final NavTabValue? value;
}
