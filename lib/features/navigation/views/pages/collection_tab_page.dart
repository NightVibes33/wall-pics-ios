import 'dart:math' as math;
import 'dart:ui';

import 'package:Prism/core/interaction/prism_haptics.dart';
import 'package:Prism/core/interaction/prism_tap_scale.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/features/setups/biz/bloc/setups_bloc.j.dart';
import 'package:Prism/features/setups/domain/entities/setup_entity.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage()
class CollectionTabPage extends StatefulWidget {
  const CollectionTabPage({super.key});

  @override
  State<CollectionTabPage> createState() => _CollectionTabPageState();
}

class _CollectionTabPageState extends State<CollectionTabPage> {
  static const Color _screenColor = Color(0xFF030303);

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  _WidgetPlacement _placement = _WidgetPlacement.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SetupsBloc>().add(const SetupsEvent.started());
    });
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final remaining = _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    if (remaining < 700) {
      context.read<SetupsBloc>().add(const SetupsEvent.fetchMoreRequested());
    }
  }

  void _selectPlacement(_WidgetPlacement placement) {
    if (_placement == placement) return;
    PrismHaptics.selection();
    setState(() => _placement = placement);
  }

  void _showMyWidgets() {
    PrismHaptics.selection();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
            decoration: BoxDecoration(
              color: const Color(0xFF151515).withValues(alpha: 0.94),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
            ),
            child: const SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'My Widgets',
                    style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Saved widget templates will appear here.',
                    style: TextStyle(color: Color(0xFFB8B8B8), fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _previewTemplate(_WidgetTemplate template) {
    PrismHaptics.selection();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: template.isWide ? 2.8 : 1.0,
                  child: _WidgetTemplateImage(template: template, fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          template.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Satoshi',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_WidgetTemplate> _filteredTemplates(List<SetupEntity> setups) {
    final query = _normalize(_searchController.text);
    final templates = _templatesFor(setups, _placement);
    if (query.isEmpty) return templates;
    return templates.where((template) {
      final haystack = _normalize('${template.title} ${template.setupName} ${template.description}');
      return haystack.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenColor,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<SetupsBloc, SetupsState>(
          builder: (context, state) {
            final templates = _filteredTemplates(state.items);
            final loading = state.status == LoadStatus.initial || (state.status == LoadStatus.loading && state.items.isEmpty);
            return RefreshIndicator(
              color: Colors.white,
              backgroundColor: Colors.black,
              onRefresh: () async {
                context.read<SetupsBloc>().add(const SetupsEvent.refreshRequested());
                await context.read<SetupsBloc>().stream.firstWhere((next) => next.status != LoadStatus.loading);
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: _WidgetHeader(
                      controller: _searchController,
                      hasText: _searchController.text.trim().isNotEmpty,
                      onClear: () => _searchController.clear(),
                      onMyWidgets: _showMyWidgets,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _PlacementTabs(active: _placement, onSelected: _selectPlacement),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
                      child: Text(
                        _placement == _WidgetPlacement.home ? 'Home Screen Widgets' : 'Lock Screen Widgets',
                        style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 31, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  if (loading)
                    const SliverToBoxAdapter(child: _WidgetSkeletonGrid())
                  else if (templates.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyWidgets())
                  else
                    SliverToBoxAdapter(
                      child: _WidgetTemplateWrap(
                        templates: templates,
                        onTap: _previewTemplate,
                      ),
                    ),
                  if (state.isFetchingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 10, bottom: 140),
                        child: Center(child: CircularProgressIndicator(color: Colors.white)),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 180)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WidgetHeader extends StatelessWidget {
  const _WidgetHeader({required this.controller, required this.hasText, required this.onClear, required this.onMyWidgets});

  final TextEditingController controller;
  final bool hasText;
  final VoidCallback onClear;
  final VoidCallback onMyWidgets;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF080808),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: TextField(
                controller: controller,
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 25, fontWeight: FontWeight.w600),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 17, right: 6),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 18, right: 10),
                    child: Icon(JamIcons.search, color: Colors.white, size: 31),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 62),
                  hintText: 'Photo widget',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontFamily: 'Satoshi', fontSize: 25, fontWeight: FontWeight.w600),
                  suffixIcon: hasText
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: onClear,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          PrismTapScale(
            pressedScale: 0.96,
            child: SizedBox(
              height: 64,
              width: 138,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onMyWidgets,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: <Color>[Color(0xFF38B8FF), Color(0xFF0878FF)]),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: <BoxShadow>[BoxShadow(color: const Color(0xFF0878FF).withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 9))],
                    ),
                    child: const Center(
                      child: Text(
                        'My Widgets',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacementTabs extends StatelessWidget {
  const _PlacementTabs({required this.active, required this.onSelected});

  final _WidgetPlacement active;
  final ValueChanged<_WidgetPlacement> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      child: Row(
        children: <Widget>[
          Expanded(child: _PlacementTab(label: 'HOMESCREEN', selected: active == _WidgetPlacement.home, onTap: () => onSelected(_WidgetPlacement.home))),
          Expanded(child: _PlacementTab(label: 'LOCKSCREEN', selected: active == _WidgetPlacement.lock, onTap: () => onSelected(_WidgetPlacement.lock))),
        ],
      ),
    );
  }
}

class _PlacementTab extends StatelessWidget {
  const _PlacementTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white.withValues(alpha: 0.48),
                fontFamily: 'Satoshi',
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 4,
              width: selected ? 152 : 0,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetTemplateWrap extends StatelessWidget {
  const _WidgetTemplateWrap({required this.templates, required this.onTap});

  final List<_WidgetTemplate> templates;
  final ValueChanged<_WidgetTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gap = 14.0;
    final sidePadding = 18.0;
    final halfWidth = (width - (sidePadding * 2) - gap) / 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 0),
      child: Wrap(
        spacing: gap,
        runSpacing: 22,
        children: <Widget>[
          for (final template in templates)
            _WidgetTemplateCard(
              template: template,
              width: template.isWide ? width - (sidePadding * 2) : halfWidth,
              onTap: () => onTap(template),
            ),
        ],
      ),
    );
  }
}

class _WidgetTemplateCard extends StatelessWidget {
  const _WidgetTemplateCard({required this.template, required this.width, required this.onTap});

  final _WidgetTemplate template;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageHeight = template.isWide ? math.max(104.0, width * 0.42) : width;
    return SizedBox(
      width: width,
      child: PrismTapScale(
        pressedScale: 0.97,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Column(
              children: <Widget>[
                Container(
                  height: imageHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101012),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _WidgetTemplateImage(template: template, fit: BoxFit.cover),
                      if (template.isLive)
                        Positioned(
                          left: 14,
                          bottom: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.58), borderRadius: BorderRadius.circular(999)),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(JamIcons.play_circle_f, color: Colors.white, size: 19),
                                  SizedBox(width: 7),
                                  Text('Live', style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 18, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  template.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontFamily: 'Satoshi', fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetTemplateImage extends StatelessWidget {
  const _WidgetTemplateImage({required this.template, required this.fit});

  final _WidgetTemplate template;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: template.imageUrl,
      fit: fit,
      alignment: Alignment.center,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (_, _) => const ColoredBox(color: Color(0xFF101012)),
      errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF101012)),
    );
  }
}

class _WidgetSkeletonGrid extends StatelessWidget {
  const _WidgetSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width - 50) / 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Wrap(
        spacing: 14,
        runSpacing: 22,
        children: <Widget>[
          for (var index = 0; index < 8; index++)
            Column(
              children: <Widget>[
                Container(
                  width: index == 0 ? width - 36 : cardWidth,
                  height: index == 0 ? 124 : cardWidth,
                  decoration: BoxDecoration(color: const Color(0xFF101012), borderRadius: BorderRadius.circular(18)),
                ),
                const SizedBox(height: 10),
                Container(width: 80, height: 18, decoration: BoxDecoration(color: const Color(0xFF101012), borderRadius: BorderRadius.circular(99))),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyWidgets extends StatelessWidget {
  const _EmptyWidgets();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 80, 24, 160),
      child: Center(
        child: Text(
          'No widgets found.',
          style: TextStyle(color: Colors.white70, fontFamily: 'Satoshi', fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

enum _WidgetPlacement { home, lock }

class _WidgetTemplate {
  const _WidgetTemplate({
    required this.setup,
    required this.placement,
    required this.title,
    required this.imageUrl,
    required this.isWide,
    required this.isLive,
  });

  final SetupEntity setup;
  final _WidgetPlacement placement;
  final String title;
  final String imageUrl;
  final bool isWide;
  final bool isLive;

  String get setupName => setup.name ?? '';
  String get description => setup.desc ?? '';
}

List<_WidgetTemplate> _templatesFor(List<SetupEntity> setups, _WidgetPlacement placement) {
  final templates = <_WidgetTemplate>[];
  final seen = <String>{};
  for (final setup in setups) {
    final title = _widgetTitle(setup, placement);
    final imageUrl = _widgetImageUrl(setup, placement);
    if (title.isEmpty || imageUrl.isEmpty || _isBlockedWidgetValue(title) || _isBlockedWidgetValue(imageUrl)) {
      continue;
    }
    final key = '${placement.name}|${title.toLowerCase()}|$imageUrl';
    if (!seen.add(key)) {
      continue;
    }
    templates.add(
      _WidgetTemplate(
        setup: setup,
        placement: placement,
        title: title,
        imageUrl: imageUrl,
        isWide: _isWideWidget(title, imageUrl, templates.length),
        isLive: _normalize(title).contains('live') || _normalize(setup.desc ?? '').contains('live'),
      ),
    );
  }
  return templates;
}

String _widgetTitle(SetupEntity setup, _WidgetPlacement placement) {
  final primary = placement == _WidgetPlacement.home ? setup.widget : setup.widget2;
  final fallback = placement == _WidgetPlacement.home ? setup.name : setup.widget;
  return _firstNonEmpty(<String?>[primary, fallback, setup.name, 'Photo']).trim();
}

String _widgetImageUrl(SetupEntity setup, _WidgetPlacement placement) {
  final primary = placement == _WidgetPlacement.home ? setup.widgetUrl : setup.widgetUrl2;
  final fallback = placement == _WidgetPlacement.home ? setup.image : setup.widgetUrl;
  return _firstNonEmpty(<String?>[primary, fallback, setup.image]).trim();
}

bool _isWideWidget(String title, String imageUrl, int ordinal) {
  final normalized = _normalize('$title $imageUrl');
  return normalized.contains('photo/video') || normalized.contains('polaroid') || normalized.contains('live') || ordinal % 5 == 0;
}

bool _isBlockedWidgetValue(String value) {
  final normalized = _normalize(value);
  return normalized.contains('wallpics') || normalized.contains('watermark');
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _normalize(String value) => value.trim().toLowerCase();
