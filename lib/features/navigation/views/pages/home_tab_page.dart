import 'dart:async';
import 'dart:math' as math;

import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/navigation/views/widgets/offline_banner.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_gallery_store.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

@RoutePage()
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key});

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  static const Color _screenColor = Color(0xFF141416);
  static const List<_HomeTabSpec> _tabs = <_HomeTabSpec>[
    _HomeTabSpec(label: 'FOR YOU', title: 'For You', contentType: PrismCatalogDataSource.regularContentType),
    _HomeTabSpec(label: '3D', title: '3D Spatial', contentType: PrismCatalogDataSource.parallaxContentType),
    _HomeTabSpec(label: 'FUNNY ISLAND', title: 'Funny Island', query: 'funny island'),
    _HomeTabSpec(label: 'NEW', title: 'New', contentType: PrismCatalogDataSource.regularContentType),
    _HomeTabSpec(label: '4K', title: '4K', query: '4k'),
  ];
  static const List<_HomeShortcut> _shortcuts = <_HomeShortcut>[
    _HomeShortcut(
      label: 'Live',
      icon: JamIcons.play_circle_f,
      contentType: PrismCatalogDataSource.liveContentType,
      accent: Color(0xFF2EA8FF),
    ),
    _HomeShortcut(
      label: 'Artwork',
      icon: JamIcons.picture_f,
      contentType: PrismCatalogDataSource.regularContentType,
      accent: Color(0xFF4A8DFF),
    ),
    _HomeShortcut(
      label: 'Charging',
      icon: Icons.bolt,
      contentType: PrismCatalogDataSource.chargingAnimationContentType,
      accent: Color(0xFFA6F34D),
    ),
    _HomeShortcut(
      label: 'Ringtone',
      icon: JamIcons.music_f,
      contentType: PrismCatalogDataSource.stickerContentType,
      accent: Color(0xFFFF9F2D),
    ),
    _HomeShortcut(
      label: 'PFP',
      icon: JamIcons.user_circle,
      contentType: PrismCatalogDataSource.profilePictureContentType,
      accent: Color(0xFFFF3939),
    ),
    _HomeShortcut(
      label: 'Matching',
      icon: JamIcons.pictures_f,
      contentType: PrismCatalogDataSource.matchingContentType,
      accent: Color(0xFFFF45D3),
    ),
  ];

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _precachedUrls = <String>{};

  late Future<_HomeDashboardData> _dashboardFuture;
  bool _hasConnection = true;
  int _activeTabIndex = 0;
  String _submittedQuery = '';

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    _searchController.addListener(_onSearchTextChanged);
    _checkConnection();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkConnection() async {
    final result = await InternetConnectionChecker.instance.hasConnection;
    if (mounted) {
      setState(() => _hasConnection = result);
    }
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
    await _dashboardFuture;
  }

  void _selectTab(int index) {
    if (_activeTabIndex == index) {
      return;
    }
    setState(() {
      _activeTabIndex = index;
      _submittedQuery = '';
      _searchController.clear();
      _dashboardFuture = _loadDashboard();
    });
  }

  void _submitSearch(String query) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submittedQuery = query.trim();
      _activeTabIndex = 0;
      _dashboardFuture = _loadDashboard();
    });
  }

  void _clearSearch() {
    setState(() {
      _submittedQuery = '';
      _searchController.clear();
      _dashboardFuture = _loadDashboard();
    });
  }

  Future<_HomeDashboardData> _loadDashboard() async {
    final futures = <Future<_HomeSection>>[];
    final keys = <String>{};

    void addCatalog({
      required String title,
      required String contentType,
      String slug = 'for-you',
      _SectionKind kind = _SectionKind.wallpaper,
    }) {
      final key = '$title|$contentType|$slug';
      if (!keys.add(key)) {
        return;
      }
      futures.add(_loadCatalogSection(title: title, contentType: contentType, slug: slug, kind: kind));
    }

    void addSearch({required String title, required String query}) {
      final key = 'search|$title|$query';
      if (!keys.add(key)) {
        return;
      }
      futures.add(_loadSearchSection(title: title, query: query));
    }

    final query = _submittedQuery.trim();
    if (query.isNotEmpty) {
      addSearch(title: 'For You', query: query);
    } else {
      final tab = _tabs[_activeTabIndex];
      if (tab.query != null) {
        addSearch(title: tab.title, query: tab.query!);
      } else {
        addCatalog(
          title: tab.title,
          contentType: tab.contentType ?? PrismCatalogDataSource.regularContentType,
          kind: _kindFor(tab.contentType),
        );
      }
    }

    addCatalog(title: 'Live Wallpapers', contentType: PrismCatalogDataSource.liveContentType, kind: _SectionKind.live);
    addCatalog(title: 'For You', contentType: PrismCatalogDataSource.regularContentType);
    addCatalog(title: 'DIY Live Wallpapers', contentType: PrismCatalogDataSource.liveDiyTemplateContentType, kind: _SectionKind.live);
    addCatalog(title: 'Charging', contentType: PrismCatalogDataSource.chargingAnimationContentType, kind: _SectionKind.charging);
    addCatalog(title: '3D Spatial', contentType: PrismCatalogDataSource.parallaxContentType);
    addCatalog(title: 'Matching', contentType: PrismCatalogDataSource.matchingContentType, kind: _SectionKind.matching);
    addCatalog(title: 'Profile Pictures', contentType: PrismCatalogDataSource.profilePictureContentType, kind: _SectionKind.profile);

    final sections = (await Future.wait<_HomeSection>(futures))
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
    return _HomeDashboardData(sections: sections);
  }

  Future<_HomeSection> _loadCatalogSection({
    required String title,
    required String contentType,
    required String slug,
    required _SectionKind kind,
  }) async {
    try {
      final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(
        category: CategoryEntity(
          name: title,
          source: WallpaperSource.prism,
          searchType: CategorySearchType.nonSearch,
          image: '',
          image2: '',
          catalogSlug: slug,
          catalogContentType: contentType,
        ),
        refresh: true,
      );
      return _HomeSection(
        title: title,
        contentType: contentType,
        slug: slug,
        kind: kind,
        items: _uniqueItems(page?.items ?? const <FeedItemEntity>[]).take(12).toList(growable: false),
      );
    } catch (_) {
      return _HomeSection.empty(title: title, contentType: contentType, slug: slug, kind: kind);
    }
  }

  Future<_HomeSection> _loadSearchSection({required String title, required String query}) async {
    try {
      final page = await PrismCatalogDataSource.instance.search(query: query, refresh: true);
      return _HomeSection(
        title: title,
        contentType: PrismCatalogDataSource.regularContentType,
        slug: 'for-you',
        kind: _SectionKind.wallpaper,
        items: _uniqueItems(page.items).take(12).toList(growable: false),
      );
    } catch (_) {
      return _HomeSection.empty(
        title: title,
        contentType: PrismCatalogDataSource.regularContentType,
        slug: 'for-you',
        kind: _SectionKind.wallpaper,
      );
    }
  }

  List<FeedItemEntity> _uniqueItems(Iterable<FeedItemEntity> items) {
    final seen = <String>{};
    return <FeedItemEntity>[
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }

  _SectionKind _kindFor(String? contentType) {
    return switch (contentType) {
      PrismCatalogDataSource.liveContentType => _SectionKind.live,
      PrismCatalogDataSource.liveDiyTemplateContentType => _SectionKind.live,
      PrismCatalogDataSource.matchingContentType => _SectionKind.matching,
      PrismCatalogDataSource.doubleContentType => _SectionKind.matching,
      PrismCatalogDataSource.profilePictureContentType => _SectionKind.profile,
      PrismCatalogDataSource.chargingAnimationContentType => _SectionKind.charging,
      _ => _SectionKind.wallpaper,
    };
  }

  void _openCatalog({required String title, required String contentType, String slug = 'for-you'}) {
    if (contentType == PrismCatalogDataSource.matchingContentType ||
        contentType == PrismCatalogDataSource.doubleContentType) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _MatchingCatalogScreen(title: title, contentType: contentType, slug: slug),
        ),
      );
      return;
    }
    final encodedName = Uri.encodeComponent('$contentType|$slug|$title');
    context.router.push(CollectionViewRoute(collectionName: 'category:$encodedName'));
  }

  void _precacheDashboardImages(_HomeDashboardData data) {
    final urls = data.sections
        .expand((section) => section.items)
        .expand((item) {
          final paired = WallpaperTile.pairedImageUrlsForItem(item);
          return paired.isNotEmpty ? paired : <String>[item.thumbnailUrl.trim()];
        })
        .where((url) => url.isNotEmpty)
        .take(54)
        .where(_precachedUrls.add)
        .toList(growable: false);
    if (urls.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final url in urls) {
        unawaited(precacheImage(CachedNetworkImageProvider(url), context).catchError((Object _) {}));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenColor,
      body: Stack(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: FutureBuilder<_HomeDashboardData>(
              future: _dashboardFuture,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data != null) {
                  _precacheDashboardImages(data);
                }
                return RefreshIndicator(
                  color: Colors.white,
                  backgroundColor: Colors.black,
                  onRefresh: _refreshDashboard,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: _SearchHeader(
                          controller: _searchController,
                          hasText: _searchController.text.trim().isNotEmpty,
                          onSubmitted: _submitSearch,
                          onClear: _clearSearch,
                        ),
                      ),
                      SliverToBoxAdapter(child: _HeroBanner(imageUrl: data?.firstPreviewUrl)),
                      SliverToBoxAdapter(
                        child: _ShortcutRow(
                          shortcuts: _shortcuts,
                          onSelected: (shortcut) => _openCatalog(title: shortcut.label, contentType: shortcut.contentType),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _CatalogPanel(
                          tabs: _tabs,
                          activeTabIndex: _activeTabIndex,
                          loading: snapshot.connectionState == ConnectionState.waiting && data == null,
                          sections: data?.sections ?? const <_HomeSection>[],
                          onTabSelected: _selectTab,
                          onMore: (section) => _openCatalog(
                            title: section.title,
                            contentType: section.contentType,
                            slug: section.slug,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (!_hasConnection) ConnectivityWidget(),
        ],
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.hasText,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasText;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

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
                color: const Color(0xFF050506),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: TextField(
                controller: controller,
                cursorColor: Colors.white,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Satoshi',
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 17, right: 8),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 18, right: 10),
                    child: Icon(JamIcons.search, color: Colors.white, size: 31),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 62),
                  hintText: 'Search',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.28),
                    fontFamily: 'Satoshi',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
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
          const SizedBox(width: 14),
          SizedBox(
            width: 102,
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: <Color>[Color(0xFF4BB7FF), Color(0xFF0076FF)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: const Color(0xFF0076FF).withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(JamIcons.crown_f, color: Colors.white, size: 28),
                  SizedBox(width: 9),
                  Text(
                    'Pro',
                    style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 27, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 104,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (url.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => const ColoredBox(color: Color(0xFF050506)),
                  errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF050506)),
                )
              else
                const ColoredBox(color: Color(0xFF050506)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[Colors.black, Colors.black.withValues(alpha: 0.42), Colors.black.withValues(alpha: 0.08)],
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 28),
                  child: Text(
                    'Prism',
                    style: TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 39, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.shortcuts, required this.onSelected});

  final List<_HomeShortcut> shortcuts;
  final ValueChanged<_HomeShortcut> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => _ShortcutTile(shortcut: shortcuts[index], onTap: () => onSelected(shortcuts[index])),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: shortcuts.length,
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.shortcut, required this.onTap});

  final _HomeShortcut shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF202023),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: shortcut.accent, width: 1.4),
              boxShadow: <BoxShadow>[
                BoxShadow(color: shortcut.accent.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(shortcut.icon, color: Colors.white, size: 28),
                const SizedBox(height: 7),
                Text(
                  shortcut.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogPanel extends StatelessWidget {
  const _CatalogPanel({
    required this.tabs,
    required this.activeTabIndex,
    required this.loading,
    required this.sections,
    required this.onTabSelected,
    required this.onMore,
  });

  final List<_HomeTabSpec> tabs;
  final int activeTabIndex;
  final bool loading;
  final List<_HomeSection> sections;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<_HomeSection> onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.only(top: 18),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopTabs(tabs: tabs, activeIndex: activeTabIndex, onSelected: onTabSelected),
          if (loading)
            const _DashboardSkeleton()
          else if (sections.isEmpty)
            const _EmptyDashboard()
          else
            for (final section in sections) _WallpaperSection(section: section, onMore: () => onMore(section)),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.tabs, required this.activeIndex, required this.onSelected});

  final List<_HomeTabSpec> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final selected = activeIndex == index;
          return InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelected(index),
            child: SizedBox(
              height: 54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tabs[index].label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.48),
                      fontFamily: 'Satoshi',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: selected ? 72 : 0,
                    height: 3,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 30),
        itemCount: tabs.length,
      ),
    );
  }
}

class _WallpaperSection extends StatelessWidget {
  const _WallpaperSection({required this.section, required this.onMore});

  final _HomeSection section;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = math.max(98.0, (width - 56) / 3);
    final cardHeight = section.kind == _SectionKind.profile ? cardWidth : cardWidth * 1.92;
    final itemWidth = section.kind == _SectionKind.matching ? (cardWidth * 2) + 4 : cardWidth;
    final sourceItems = section.kind == _SectionKind.matching
        ? section.items.where((item) => WallpaperTile.pairedImageUrlsForItem(item).length >= 2)
        : section.items;
    final galleryItems = sourceItems.toList(growable: false);
    final visibleItems = galleryItems.take(9).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Satoshi',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _MoreButton(onPressed: onMore),
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 18),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: itemWidth,
                  child: _HomeWallpaperCard(
                    item: visibleItems[index],
                    index: index,
                    section: section,
                    galleryItems: galleryItems,
                  ),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemCount: visibleItems.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeWallpaperCard extends StatelessWidget {
  const _HomeWallpaperCard({
    required this.item,
    required this.index,
    required this.section,
    required this.galleryItems,
  });

  final FeedItemEntity item;
  final int index;
  final _HomeSection section;
  final List<FeedItemEntity> galleryItems;

  @override
  Widget build(BuildContext context) {
    final paired = WallpaperTile.pairedImageUrlsForItem(item);
    final image = paired.length >= 2 ? _pairedImage(context, paired) : _image(context, item.thumbnailUrl);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          WallpaperDetailGalleryStore.setFromFeedItems(items: galleryItems, index: index);
          context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(item)));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              image,
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              if (section.kind == _SectionKind.live || section.kind == _SectionKind.charging || section.kind == _SectionKind.matching)
                Positioned(left: 8, top: 8, child: _MediaBadge(kind: section.kind)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pairedImage(BuildContext context, List<String> urls) {
    final sides = urls.take(2).toList(growable: false);
    return Row(
      children: <Widget>[
        Expanded(child: _image(context, sides[0])),
        const SizedBox(width: 3, child: ColoredBox(color: Colors.black)),
        Expanded(child: _image(context, sides[1])),
      ],
    );
  }

  Widget _image(BuildContext context, String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return const ColoredBox(color: Color(0xFF111114));
    }
    final size = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheWidth = ((size.width / 3) * pixelRatio).ceil();
    final cacheHeight = (cacheWidth * 2).ceil();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.medium,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (_, _) => const ColoredBox(color: Color(0xFF111114)),
      errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF111114)),
    );
  }
}

class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.kind});

  final _SectionKind kind;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      _SectionKind.charging => Icons.bolt,
      _SectionKind.matching => JamIcons.pictures_f,
      _ => JamIcons.play_circle_f,
    };
    final label = switch (kind) {
      _SectionKind.charging => 'Charge',
      _SectionKind.matching => 'Set',
      _ => 'Live',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white, width: 1.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.only(left: 14, right: 10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('More', style: TextStyle(fontFamily: 'Satoshi', fontSize: 17, fontWeight: FontWeight.w800)),
            Icon(Icons.chevron_right, size: 21),
          ],
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = math.max(98.0, (width - 56) / 3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SkeletonBox(width: 180, height: 34, radius: 7),
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
              for (var index = 0; index < 3; index++) ...<Widget>[
                _SkeletonBox(width: cardWidth, height: cardWidth * 1.92, radius: 8),
                if (index < 2) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 28),
          const _SkeletonBox(width: 132, height: 34, radius: 7),
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
              for (var index = 0; index < 3; index++) ...<Widget>[
                _SkeletonBox(width: cardWidth, height: cardWidth * 1.92, radius: 8),
                if (index < 2) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height, required this.radius});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xFF18181C), borderRadius: BorderRadius.circular(radius)),
      child: SizedBox(width: width, height: height),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 80, 24, 160),
      child: Center(
        child: Text(
          'No wallpapers loaded. Pull to retry.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}


class _MatchingCatalogScreen extends StatefulWidget {
  const _MatchingCatalogScreen({required this.title, required this.contentType, required this.slug});

  final String title;
  final String contentType;
  final String slug;

  @override
  State<_MatchingCatalogScreen> createState() => _MatchingCatalogScreenState();
}

class _MatchingCatalogScreenState extends State<_MatchingCatalogScreen> {
  static const List<String> _sortLabels = <String>['Hot', 'New', 'Popular'];

  final ScrollController _scrollController = ScrollController();
  final Set<String> _seenIds = <String>{};

  List<_MatchingCatalogTab> _tabs = const <_MatchingCatalogTab>[
    _MatchingCatalogTab(label: 'For You', slug: 'for-you'),
  ];
  List<FeedItemEntity> _items = <FeedItemEntity>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _activeTabIndex = 0;
  int _sortIndex = 0;

  _MatchingCatalogTab get _activeTab => _tabs[_activeTabIndex.clamp(0, _tabs.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    unawaited(_loadTabs());
    unawaited(_loadPage(refresh: true));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTabs() async {
    try {
      final categories = await PrismCatalogDataSource.instance.loadCategories();
      final seen = <String>{'for-you'};
      final tabs = <_MatchingCatalogTab>[
        const _MatchingCatalogTab(label: 'For You', slug: 'for-you'),
      ];
      for (final category in categories) {
        final contentType = category.catalogContentType?.trim();
        final slug = category.catalogSlug?.trim();
        final name = category.name.trim();
        if (contentType != widget.contentType || slug == null || slug.isEmpty || name.isEmpty) {
          continue;
        }
        if (seen.add(slug)) {
          tabs.add(_MatchingCatalogTab(label: name, slug: slug));
        }
        if (tabs.length >= 8) {
          break;
        }
      }
      if (!mounted) return;
      final requestedIndex = tabs.indexWhere((tab) => tab.slug == widget.slug);
      final nextIndex = requestedIndex >= 0 ? requestedIndex : 0;
      final shouldReload = nextIndex != _activeTabIndex;
      setState(() {
        _tabs = tabs;
        _activeTabIndex = nextIndex;
      });
      if (shouldReload) {
        unawaited(_loadPage(refresh: true));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tabs = const <_MatchingCatalogTab>[_MatchingCatalogTab(label: 'For You', slug: 'for-you')];
        _activeTabIndex = 0;
      });
    }
  }

  Future<void> _loadPage({required bool refresh}) async {
    if (_loadingMore || (!refresh && !_hasMore)) return;
    if (refresh) {
      setState(() {
        _loading = true;
        _hasMore = true;
        _items = <FeedItemEntity>[];
        _seenIds.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final page = await PrismCatalogDataSource.instance.fetchCategoryFeed(
        category: CategoryEntity(
          name: _activeTab.label,
          source: WallpaperSource.prism,
          searchType: CategorySearchType.nonSearch,
          image: '',
          image2: '',
          catalogSlug: _activeTab.slug,
          catalogContentType: widget.contentType,
        ),
        refresh: refresh,
      );
      final incoming = (page?.items ?? const <FeedItemEntity>[])
          .where((item) => WallpaperTile.pairedImageUrlsForItem(item).length >= 2)
          .where((item) => _seenIds.add(item.id))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = refresh ? incoming : <FeedItemEntity>[..._items, ...incoming];
        _hasMore = page?.hasMore ?? false;
        _loading = false;
        _loadingMore = false;
      });
      _precacheVisiblePairs();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) return;
    final remaining = _scrollController.position.maxScrollExtent - _scrollController.offset;
    if (remaining < 700) {
      unawaited(_loadPage(refresh: false));
    }
  }

  void _selectTab(int index) {
    if (index == _activeTabIndex) return;
    setState(() => _activeTabIndex = index);
    unawaited(_loadPage(refresh: true));
  }

  void _selectSort(int index) {
    if (index == _sortIndex) return;
    setState(() => _sortIndex = index);
  }

  void _precacheVisiblePairs() {
    final urls = _items
        .take(10)
        .expand(WallpaperTile.pairedImageUrlsForItem)
        .where((url) => url.trim().isNotEmpty)
        .take(20)
        .toList(growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in urls) {
        unawaited(precacheImage(CachedNetworkImageProvider(url), context).catchError((Object _) {}));
      }
    });
  }

  List<FeedItemEntity> get _displayItems {
    final items = List<FeedItemEntity>.of(_items);
    if (_sortIndex == 1) {
      items.sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
    } else if (_sortIndex == 2) {
      items.sort((a, b) => b.id.compareTo(a.id));
    }
    return items;
  }

  DateTime _createdAt(FeedItemEntity item) {
    return item.when(
      prism: (_, wallpaper) => wallpaper.core.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      wallhaven: (_, _) => DateTime.fromMillisecondsSinceEpoch(0),
      pexels: (_, _) => DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayItems = _displayItems;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _MatchingCatalogHeader(title: widget.title == 'Matching' ? 'Matching Wallpapers' : widget.title),
                _MatchingCatalogTabs(tabs: _tabs, activeIndex: _activeTabIndex, onSelected: _selectTab),
                Expanded(
                  child: RefreshIndicator(
                    color: Colors.white,
                    backgroundColor: Colors.black,
                    onRefresh: () => _loadPage(refresh: true),
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: <Widget>[
                        if (_loading && displayItems.isEmpty)
                          const _MatchingCatalogSkeleton()
                        else if (displayItems.isEmpty)
                          const _MatchingCatalogEmpty()
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, sliverIndex) {
                                if (sliverIndex.isOdd) {
                                  return const SizedBox(height: 14);
                                }
                                final index = sliverIndex ~/ 2;
                                return _MatchingPairListItem(
                                  item: displayItems[index],
                                  index: index,
                                  galleryItems: displayItems,
                                );
                              },
                              childCount: (displayItems.length * 2) - 1,
                            ),
                          ),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(child: CircularProgressIndicator(color: Colors.white)),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 116)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 22,
              child: _MatchingSortBar(labels: _sortLabels, activeIndex: _sortIndex, onSelected: _selectSort),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchingCatalogHeader extends StatelessWidget {
  const _MatchingCatalogHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: SizedBox(
                width: 58,
                height: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181A),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(JamIcons.chevron_left, color: Colors.white, size: 34),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 92),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 28, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchingCatalogTabs extends StatelessWidget {
  const _MatchingCatalogTabs({required this.tabs, required this.activeIndex, required this.onSelected});

  final List<_MatchingCatalogTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 26),
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelected(index),
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tabs[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      fontFamily: 'Satoshi',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: active ? 70 : 0,
                    height: 3,
                    decoration: BoxDecoration(color: const Color(0xFF1AA0FF), borderRadius: BorderRadius.circular(999)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MatchingPairListItem extends StatelessWidget {
  const _MatchingPairListItem({required this.item, required this.index, required this.galleryItems});

  final FeedItemEntity item;
  final int index;
  final List<FeedItemEntity> galleryItems;

  @override
  Widget build(BuildContext context) {
    final urls = WallpaperTile.pairedImageUrlsForItem(item).take(2).toList(growable: false);
    if (urls.length < 2) {
      return const SizedBox.shrink();
    }
    final width = MediaQuery.sizeOf(context).width - 36;
    final height = ((width - 3) / 2) * 1.78;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheWidth = (((width - 3) / 2) * pixelRatio).ceil();
    final cacheHeight = (height * pixelRatio).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            WallpaperDetailGalleryStore.setFromFeedItems(items: galleryItems, index: index);
            context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(item)));
          },
          child: SizedBox(
            height: height,
            child: Row(
              children: <Widget>[
                Expanded(child: _MatchingCatalogImage(url: urls[0], cacheWidth: cacheWidth, cacheHeight: cacheHeight)),
                const SizedBox(width: 3, child: ColoredBox(color: Colors.black)),
                Expanded(child: _MatchingCatalogImage(url: urls[1], cacheWidth: cacheWidth, cacheHeight: cacheHeight)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchingCatalogImage extends StatelessWidget {
  const _MatchingCatalogImage({required this.url, required this.cacheWidth, required this.cacheHeight});

  final String url;
  final int cacheWidth;
  final int cacheHeight;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.medium,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (_, _) => const ColoredBox(color: Color(0xFF111114)),
      errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF111114)),
    );
  }
}

class _MatchingSortBar extends StatelessWidget {
  const _MatchingSortBar({required this.labels, required this.activeIndex, required this.onSelected});

  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1E).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          children: List<Widget>.generate(labels.length, (index) {
            final active = index == activeIndex;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: InkWell(
                  borderRadius: BorderRadius.circular(19),
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF696970) : Colors.transparent,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[index],
                      style: const TextStyle(color: Colors.white, fontFamily: 'Satoshi', fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _MatchingCatalogSkeleton extends StatelessWidget {
  const _MatchingCatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 36;
    final height = ((width - 3) / 2) * 1.78;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, sliverIndex) {
          if (sliverIndex.isOdd) {
            return const SizedBox(height: 14);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              height: height,
              child: Row(
                children: const <Widget>[
                  Expanded(child: _MatchingSkeletonPane()),
                  SizedBox(width: 3),
                  Expanded(child: _MatchingSkeletonPane()),
                ],
              ),
            ),
          );
        },
        childCount: 5,
      ),
    );
  }
}

class _MatchingSkeletonPane extends StatelessWidget {
  const _MatchingSkeletonPane();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF141416));
  }
}

class _MatchingCatalogEmpty extends StatelessWidget {
  const _MatchingCatalogEmpty();

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 120, 24, 140),
        child: Center(
          child: Text(
            'No matching pairs loaded. Pull to retry.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _MatchingCatalogTab {
  const _MatchingCatalogTab({required this.label, required this.slug});

  final String label;
  final String slug;
}

class _HomeDashboardData {
  const _HomeDashboardData({required this.sections});

  final List<_HomeSection> sections;

  String get firstPreviewUrl {
    for (final section in sections) {
      for (final item in section.items) {
        final url = item.thumbnailUrl.trim();
        if (url.isNotEmpty) {
          return url;
        }
      }
    }
    return '';
  }
}

class _HomeSection {
  const _HomeSection({
    required this.title,
    required this.contentType,
    required this.slug,
    required this.kind,
    required this.items,
  });

  factory _HomeSection.empty({
    required String title,
    required String contentType,
    required String slug,
    required _SectionKind kind,
  }) {
    return _HomeSection(title: title, contentType: contentType, slug: slug, kind: kind, items: const <FeedItemEntity>[]);
  }

  final String title;
  final String contentType;
  final String slug;
  final _SectionKind kind;
  final List<FeedItemEntity> items;
}

class _HomeTabSpec {
  const _HomeTabSpec({required this.label, required this.title, this.contentType, this.query});

  final String label;
  final String title;
  final String? contentType;
  final String? query;
}

class _HomeShortcut {
  const _HomeShortcut({required this.label, required this.icon, required this.contentType, required this.accent});

  final String label;
  final IconData icon;
  final String contentType;
  final Color accent;
}

enum _SectionKind { wallpaper, live, matching, profile, charging }
