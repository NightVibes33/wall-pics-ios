import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:flutter/material.dart';

class HeadingChipBar extends StatelessWidget {
  final String current;
  const HeadingChipBar({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final Color foreground = Theme.of(context).colorScheme.secondary;
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leadingWidth: 68,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
        child: Material(
          color: const Color(0xFF101217),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).maybePop(),
            child: Icon(JamIcons.chevron_left, color: foreground),
          ),
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.displaySmall!.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(
              'Curated by Prism',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
            ) ??
                Text(
                  'Curated by Prism',
                  style: TextStyle(color: foreground.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600),
                ),
          ],
        ),
      ),
    );
  }
}
