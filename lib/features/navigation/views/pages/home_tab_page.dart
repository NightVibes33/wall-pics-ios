import 'dart:async';
import 'dart:math' as math;

import 'package:Prism/core/purchases/paywall_orchestrator.dart';
import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/core/widgets/common/autoplay_video_preview.dart';
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/domain/entities/feed_item_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_tile.dart';
import 'package:Prism/features/navigation/views/widgets/offline_banner.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_entity.dart';
import 'package:Prism/features/palette/domain/entities/wallpaper_detail_gallery_store.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/features/user_search/views/pages/search_screen.dart';
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
    _HomeTabSpec(label: 'NEW', title: 'New', contentType: PrismCatalogDataSource.regularContentType, slug: 'newest'),
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
      label: '3D',
      icon: JamIcons.box_f,
      contentType: PrismCatalogDataSource.parallaxContentType,
      accent: Color(0xFF8BE36C),
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
  final ScrollController _scrollController = ScrollController();
  final Set<String> _precachedUrls = <String>{};
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};

  List<_HomeSection> _latestSections = const <_HomeSection>[];
  String? _activeVideoSectionKey;

  late Future<_HomeDashboardData> _dashboardFuture;
  bool _hasConnection = true;
  int _activeTabIndex = 0;
  String _submittedQuery = '';

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    _searchController.addListener(_onSearchTextChanged);
    _scrollController.addListener(_updateActiveVideoSection);
    _checkConnection();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _scrollController.removeListener(_updateActiveVideoSection);
    _searchController.dispose();
    _scrollController.dispose();
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
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.text = trimmed;
    _searchController.selection = TextSelection.collapsed(offset: trimmed.length);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchScreen(initialQuery: trimmed)));
  }

  void _clearSearch() {
    setState(() {
      _submittedQuery = '';
      _searchController.clear();
      _dashboardFuture = _loadDashboard();
    });
  }

  GlobalKey _sectionKeyFor(_HomeSection section) {
    return _sectionKeys.putIfAbsent(section.playbackKey, () => GlobalKey());
  }

  void _captureDashboardData(_HomeDashboardData? data) {
    final sections = data?.sections ?? const <_HomeSection>[];
    _latestSections = sections;
    final liveKeys = sections.map((section) => section.playbackKey).toSet();
    _sectionKeys.removeWhere((key, _) => !liveKeys.contains(key));
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveVideoSection());
  }

  void _updateActiveVideoSection() {
    if (!mounted || _latestSections.isEmpty) {
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final viewportTop = mediaQuery.padding.top + 4;
    final viewportBottom = mediaQuery.size.height - mediaQuery.padding.bottom - 112;
    var bestScore = 0.0;
    String? bestKey;
    for (final section in _latestSections) {
      if (section.kind != _SectionKind.live) {
        continue;
      }
      final renderObject = _sectionKeys[section.playbackKey]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final height = renderObject.size.height;
      if (height <= 0) {
        continue;
      }
      final bottom = top + height;
      final visible = math.min(bottom, viewportBottom) - math.max(top, viewportTop);
      final score = math.max(0.0, visible) / height;
      if (score > bestScore) {
        bestScore = score;
        bestKey = section.playbackKey;
      }
    }
    if (bestScore < 0.28) {
      bestKey = null;
    }
    if (bestKey != _activeVideoSectionKey) {
      setState(() => _activeVideoSectionKey = bestKey);
    }
  }

  Future<_HomeDashboardData> _loadDashboard() async {
    final query = _submittedQuery.trim();
    final activeTab = _tabs[_activeTabIndex];
    if (query.isEmpty && activeTab.query == null) {
      final bootstrap = await PrismCatalogDataSource.instance.fetchHomeBootstrap();
      final bootstrapped = _dashboardFromBootstrap(bootstrap, activeTab);
      if (bootstrapped != null) {
        return bootstrapped;
      }
    }

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
          slug: tab.slug ?? 'for-you',
          kind: _kindFor(tab.contentType),
        );
      }
    }

    addCatalog(title: 'Live Wallpapers', contentType: PrismCatalogDataSource.liveContentType, kind: _SectionKind.live);
    addCatalog(title: 'For You', contentType: PrismCatalogDataSource.regularContentType);
    addCatalog(title: '3D Spatial', contentType: PrismCatalogDataSource.parallaxContentType);
    addCatalog(title: 'Matching', contentType: PrismCatalogDataSource.matchingContentType, kind: _SectionKind.matching);
    addCatalog(title: 'Profile Pictures', contentType: PrismCatalogDataSource.profilePictureContentType, kind: _SectionKind.profile);

    final sections = (await Future.wait<_HomeSection>(futures))
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
    return _HomeDashboardData(sections: sections);
  }

  _HomeDashboardData? _dashboardFromBootstrap(PrismCatalogHomeBootstrap? bootstrap, _HomeTabSpec activeTab) {
    if (bootstrap == null || bootstrap.sections.isEmpty) {
      return null;
    }

    final sections = <_HomeSection>[];
    for (final section in bootstrap.sections) {
      final items = _uniqueItems(section.items).take(18).toList(growable: false);
      if (items.isEmpty) {
        continue;
      }
      sections.add(
        _HomeSection(
          title: section.title,
          contentType: section.contentType,
          slug: section.slug,
          kind: _kindForBootstrap(section.kind, section.contentType),
          items: items,
        ),
      );
    }
    if (sections.isEmpty) {
      return null;
    }

    final activeContentType = activeTab.contentType ?? PrismCatalogDataSource.regularContentType;
    final activeSlug = activeTab.slug ?? 'for-you';
    sections.sort((a, b) {
      final aActive = a.contentType == activeContentType && a.slug == activeSlug ? 0 : 1;
      final bActive = b.contentType == activeContentType && b.slug == activeSlug ? 0 : 1;
      if (aActive != bActive) return aActive.compareTo(bActive);
      return 0;
    });
    return _HomeDashboardData(sections: sections);
  }

  _SectionKind _kindForBootstrap(String kind, String contentType) {
    return switch (kind.trim()) {
      'live' => _SectionKind.live,
      'matching' => _SectionKind.matching,
      'profile' => _SectionKind.profile,
      _ => _kindFor(contentType),
    };
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
      final page = await PrismCatalogDataSource.instance.search(query: query, refresh: true, scanFullIndex: false);
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
      PrismCatalogDataSource.matchingContentType => _SectionKind.matching,
      PrismCatalogDataSource.doubleContentType => _SectionKind.matching,
      PrismCatalogDataSource.profilePictureContentType => _SectionKind.profile,
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
          final paired = WallpaperTile.pairedPreviewUrlsForItem(item);
          if (paired.isNotEmpty) return paired;
          final thumbnailUrl = item.thumbnailUrl.trim();
          final thumbnailPath = Uri.tryParse(thumbnailUrl)?.path.toLowerCase() ?? thumbnailUrl.toLowerCase();
          if (thumbnailUrl.isEmpty || thumbnailPath.endsWith('.zip')) {
            return const <String>[];
          }
          return <String>[thumbnailUrl];
        })
        .where((url) => url.isNotEmpty)
        .take(36)
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
                _captureDashboardData(data);
                if (data != null) {
                  _precacheDashboardImages(data);
                }
                return RefreshIndicator(
                  color: Colors.white,
                  backgroundColor: Colors.black,
                  onRefresh: _refreshDashboard,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: _SearchHeader(
                          controller: _searchController,
                          hasText: _searchController.text.trim().isNotEmpty,
                          onSubmitted: _submitSearch,
                          onClear: _clearSearch,
                          onProTap: () => PaywallOrchestrator.instance.present(
                            context,
                            placement: PaywallPlacement.mainUpsell,
                            source: 'home_pro_button',
                          ),
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
                          activeVideoSectionKey: _activeVideoSectionKey,
                          sectionKeyFor: _sectionKeyFor,
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
    required this.onProTap,
  });

  final TextEditingController controller;
  final bool hasText;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onProTap;

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
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onProTap,
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
    required this.activeVideoSectionKey,
    required this.sectionKeyFor,
    required this.onTabSelected,
    required this.onMore,
  });

  final List<_HomeTabSpec> tabs;
  final int activeTabIndex;
  final bool loading;
  final List<_HomeSection> sections;
  final String? activeVideoSectionKey;
  final GlobalKey Function(_HomeSection section) sectionKeyFor;
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
            for (final section in sections)
              KeyedSubtree(
                key: sectionKeyFor(section),
                child: _WallpaperSection(
                  section: section,
                  playVideo: section.kind == _SectionKind.live || activeVideoSectionKey == section.playbackKey,
                  onMore: () => onMore(section),
                ),
              ),
          const SizedBox(height: 220),
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
  const _WallpaperSection({required this.section, required this.playVideo, required this.onMore});

  final _HomeSection section;
  final bool playVideo;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = math.max(98.0, (width - 56) / 3);
    final cardHeight = section.kind == _SectionKind.profile ? cardWidth : cardWidth * 1.92;
    final sourceItems = section.kind == _SectionKind.matching
        ? WallpaperTile.matchingSideItemsForItems(section.items)
        : WallpaperTile.expandMatchingItemsForDisplay(section.items);
    final galleryItems = sourceItems.toList(growable: false);
    final visibleItems = galleryItems.take(section.kind == _SectionKind.matching ? 12 : 9).toList(growable: false);
    final titleFontSize = section.title.length > 14 ? 23.0 : 27.0;

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
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Satoshi',
                      fontSize: titleFontSize,
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
              cacheExtent: cardWidth * 8,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: cardWidth,
                  child: _HomeWallpaperCard(
                    item: visibleItems[index],
                    index: index,
                    section: section,
                    galleryItems: galleryItems,
                    playVideo: playVideo,
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
    required this.playVideo,
  });

  final FeedItemEntity item;
  final int index;
  final _HomeSection section;
  final List<FeedItemEntity> galleryItems;
  final bool playVideo;

  @override
  Widget build(BuildContext context) {
    final isProfile = section.kind == _SectionKind.profile || WallpaperTile.isProfilePictureItem(item);
    final paired = WallpaperTile.pairedPreviewUrlsForItem(item);
    final videoUrl = WallpaperTile.videoUrlForItem(item);
    final posterUrl = WallpaperTile.posterUrlForItem(item);
    final imageUrl = posterUrl.isNotEmpty ? posterUrl : item.thumbnailUrl;
    final image = paired.length >= 2
        ? _pairedImage(context, paired)
        : section.kind == _SectionKind.live && playVideo && videoUrl.isNotEmpty
            ? AutoplayVideoPreview(videoUrl: videoUrl, posterUrl: imageUrl, playing: true)
            : _image(context, imageUrl, isProfile: isProfile);
    final shape = isProfile ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: () {
          WallpaperDetailGalleryStore.setFromFeedItems(items: galleryItems, index: index);
          context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(item)));
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            image,
            DecoratedBox(
              decoration: isProfile
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    )
                  : BoxDecoration(
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(8),
                    ),
            ),
            if (section.kind == _SectionKind.live)
              Positioned(left: 8, top: 8, child: _MediaBadge(kind: section.kind)),
          ],
        ),
      ),
    );
  }

  bool _isArchiveUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.zip');
  }

  Widget _pairedImage(BuildContext context, List<String> urls) {
    final rows = <Widget>[];
    for (var index = 0; index < urls.length; index += 2) {
      rows.add(
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(child: _image(context, urls[index])),
              const SizedBox(width: 3, child: ColoredBox(color: Colors.black)),
              if (index + 1 < urls.length)
                Expanded(child: _image(context, urls[index + 1]))
              else
                const Spacer(),
            ],
          ),
        ),
      );
      if (index + 2 < urls.length) rows.add(const SizedBox(height: 3, child: ColoredBox(color: Colors.black)));
    }
    return Column(children: rows);
  }

  Widget _image(BuildContext context, String rawUrl, {bool isProfile = false}) {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return const ColoredBox(color: Color(0xFF111114));
    }
    if (_isArchiveUrl(url)) {
      return const ColoredBox(color: Color(0xFF111114));
    }
    final size = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheWidth = ((size.width / 3) * pixelRatio).ceil();
    final cacheHeight = isProfile ? cacheWidth : (cacheWidth * 2).ceil();
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
      _SectionKind.matching => JamIcons.pictures_f,
      _ => JamIcons.play_circle_f,
    };
    final label = switch (kind) {
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
      const pinnedSlugs = <String>{'friends-3801', '3-friends', '4-friends', '5-friends'};
      final seen = <String>{'for-you'};
      final allTabs = <_MatchingCatalogTab>[
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
          allTabs.add(_MatchingCatalogTab(label: name, slug: slug));
        }
      }
      final pinnedTabs = allTabs.where((tab) => pinnedSlugs.contains(tab.slug)).toList(growable: false);
      final regularTabs = allTabs
          .where((tab) => tab.slug != 'for-you' && !pinnedSlugs.contains(tab.slug))
          .take(8)
          .toList(growable: false);
      final tabs = <_MatchingCatalogTab>[
        const _MatchingCatalogTab(label: 'For You', slug: 'for-you'),
        ...pinnedTabs,
        ...regularTabs,
      ];
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
        .take(12)
        .expand(WallpaperTile.pairedPreviewUrlsForItem)
        .where((url) => url.trim().isNotEmpty)
        .take(24)
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
    final galleryItems = WallpaperTile.matchingSideItemsForItems(displayItems);
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
                                  galleryItems: galleryItems,
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
    final sideItems = WallpaperTile.matchingSideItemsForItem(item);
    if (sideItems.length < 2) {
      return const SizedBox.shrink();
    }
    final width = MediaQuery.sizeOf(context).width - 36;
    final sideWidth = (width - 3) / 2;
    final rowHeight = sideWidth * 1.78;
    final rowCount = (sideItems.length / 2).ceil();
    final height = rowHeight * rowCount + (rowCount - 1) * 3;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheWidth = (sideWidth * pixelRatio).ceil();
    final cacheHeight = (rowHeight * pixelRatio).ceil();
    final rows = <Widget>[];
    for (var sideIndex = 0; sideIndex < sideItems.length; sideIndex += 2) {
      rows.add(
        SizedBox(
          height: rowHeight,
          child: Row(
            children: <Widget>[
              Expanded(child: _MatchingCatalogSide(item: sideItems[sideIndex], galleryItems: galleryItems, cacheWidth: cacheWidth, cacheHeight: cacheHeight)),
              const SizedBox(width: 3),
              if (sideIndex + 1 < sideItems.length)
                Expanded(child: _MatchingCatalogSide(item: sideItems[sideIndex + 1], galleryItems: galleryItems, cacheWidth: cacheWidth, cacheHeight: cacheHeight))
              else
                const Spacer(),
            ],
          ),
        ),
      );
      if (sideIndex + 2 < sideItems.length) rows.add(const SizedBox(height: 3));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: height,
        child: Column(children: rows),
      ),
    );
  }
}

class _MatchingCatalogSide extends StatelessWidget {
  const _MatchingCatalogSide({required this.item, required this.galleryItems, required this.cacheWidth, required this.cacheHeight});

  final FeedItemEntity item;
  final List<FeedItemEntity> galleryItems;
  final int cacheWidth;
  final int cacheHeight;

  @override
  Widget build(BuildContext context) {
    final galleryIndex = galleryItems.indexWhere((candidate) => candidate.id == item.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          WallpaperDetailGalleryStore.setFromFeedItems(items: galleryItems, index: galleryIndex >= 0 ? galleryIndex : 0);
          context.router.push(WallpaperDetailRoute(entity: WallpaperDetailEntityX.fromFeedItem(item)));
        },
        child: _MatchingCatalogImage(url: item.thumbnailUrl, cacheWidth: cacheWidth, cacheHeight: cacheHeight),
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

  String get playbackKey => '$contentType|$slug|$title';
}

class _HomeTabSpec {
  const _HomeTabSpec({required this.label, required this.title, this.contentType, this.slug, this.query});

  final String label;
  final String title;
  final String? contentType;
  final String? slug;
  final String? query;
}

class _HomeShortcut {
  const _HomeShortcut({required this.label, required this.icon, required this.contentType, required this.accent});

  final String label;
  final IconData icon;
  final String contentType;
  final Color accent;
}

enum _SectionKind { wallpaper, live, matching, profile }
