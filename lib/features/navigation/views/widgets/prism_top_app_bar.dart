import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/global/svgAssets.dart';
import 'package:Prism/theme/app_tokens.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PrismTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PrismTopAppBar({super.key, this.onLogoTap});

  final VoidCallback? onLogoTap;

  @override
  Size get preferredSize => const Size.fromHeight(PrismAppBarSizes.height);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).primaryColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: PrismAppBarSizes.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrismAppBarSizes.horizontalPadding),
            child: Row(
              children: <Widget>[
                SizedBox(width: PrismAppBarSizes.iconButtonTouchTarget),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: onLogoTap,
                      behavior: HitTestBehavior.opaque,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _PrismLogo(),
                          SizedBox(width: 4),
                          Text('prism', style: PrismTextStyles.brandName),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => context.router.push(const SettingsRoute()),
                  icon: Icon(
                    Icons.settings_outlined,
                    size: PrismAppBarSizes.iconSize,
                    color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrismLogo extends StatelessWidget {
  const _PrismLogo();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      prismVector,
      width: 10,
      height: 12,
      colorFilter: const ColorFilter.mode(PrismColors.onPrimary, BlendMode.srcIn),
    );
  }
}
