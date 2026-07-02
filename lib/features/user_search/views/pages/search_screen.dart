import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/features/user_search/views/widgets/search_grid.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

@RoutePage()
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _screenColor = Color(0xFF07080B);
  static const _fieldColor = Color(0xFF101217);

  final TextEditingController _searchController = TextEditingController();
  late final Future<List<String>> _suggestionsFuture;
  String _submittedQuery = '';

  bool get _isSubmitted => _submittedQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = _loadSuggestions();
    final initialQuery = widget.initialQuery.trim();
    if (initialQuery.isNotEmpty) {
      _submittedQuery = initialQuery;
      _searchController.text = initialQuery;
      _searchController.selection = TextSelection.collapsed(offset: initialQuery.length);
      _trackSearchSubmitted(query: initialQuery, fromSuggestion: false, sourceContext: 'home_search_submit');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<String>> _loadSuggestions() async {
    final seen = <String>{};
    final suggestions = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) {
        return;
      }
      suggestions.add(trimmed);
    }

    for (final query in await PrismCatalogDataSource.instance.popularSearches()) {
      add(query);
    }
    final categories = await PrismCatalogDataSource.instance.loadCategories();
    for (final category in categories) {
      add(category.name);
    }
    return suggestions;
  }

  int _queryWordCount(String query) {
    return query.trim().split(RegExp(r'\s+')).where((segment) => segment.trim().isNotEmpty).length;
  }

  void _trackSearchSubmitted({required String query, required bool fromSuggestion, required String sourceContext}) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return;
    }
    analytics.track(
      SearchSubmittedEvent(
        provider: SearchProviderValue.prismCatalog,
        queryLength: trimmedQuery.length,
        queryWordCount: _queryWordCount(trimmedQuery),
        sourceContext: sourceContext,
        fromSuggestion: fromSuggestion,
      ),
    );
  }

  void _submitSearch(String query, {required bool fromSuggestion, required String sourceContext}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _trackSearchSubmitted(query: trimmed, fromSuggestion: fromSuggestion, sourceContext: sourceContext);
    setState(() {
      _submittedQuery = trimmed;
      _searchController.text = trimmed;
      _searchController.selection = TextSelection.collapsed(offset: trimmed.length);
    });
  }

  void _clearSearch() {
    setState(() {
      _submittedQuery = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _screenColor,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xFF10141B), Color(0xFF0A0B0F), Color(0xFF060608)],
                    stops: <double>[0.0, 0.28, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (canPop) ...<Widget>[
                        _ChromeIconButton(
                          tooltip: 'Back',
                          icon: Icons.arrow_back_ios_new,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Search Prism',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Satoshi',
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isSubmitted
                                  ? 'Results for your latest search.'
                                  : 'Explore wallpapers, matching sets, 3D Spatial, and PFPs.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'Satoshi',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                  child: _SearchField(
                    controller: _searchController,
                    isSubmitted: _isSubmitted,
                    onChanged: (text) {
                      if (text.trim().isEmpty && _isSubmitted) {
                        _clearSearch();
                      }
                    },
                    onClear: _clearSearch,
                    onSubmit: (text, sourceContext) => _submitSearch(
                      text,
                      fromSuggestion: false,
                      sourceContext: sourceContext,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: _isSubmitted
                        ? KeyedSubtree(
                            key: ValueKey<String>('results:${_submittedQuery.trim().toLowerCase()}'),
                            child: SearchGrid(query: _submittedQuery),
                          )
                        : KeyedSubtree(
                            key: const ValueKey<String>('suggestions'),
                            child: _SearchSuggestions(
                              future: _suggestionsFuture,
                              onSelected: _submitSearch,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101217),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.isSubmitted,
    required this.onChanged,
    required this.onClear,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final void Function(String text, String sourceContext) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: _SearchScreenState._fieldColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        keyboardAppearance: Brightness.dark,
        cursorColor: Colors.white,
        style: const TextStyle(
          fontFamily: 'Satoshi',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (text) => onSubmit(text, 'search_textfield'),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.only(top: 18, bottom: 16),
          border: InputBorder.none,
          disabledBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Icon(JamIcons.search, color: Colors.white, size: 24),
          hintText: 'Search wallpapers, sets, or creators',
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.34),
          ),
          suffixIcon: IconButton(
            tooltip: isSubmitted ? 'Clear search' : 'Search',
            icon: Icon(isSubmitted ? Icons.close : JamIcons.search, color: Colors.white, size: isSubmitted ? 22 : 23),
            onPressed: isSubmitted ? onClear : () => onSubmit(controller.text, 'search_icon'),
          ),
        ),
      ),
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({required this.future, required this.onSelected});

  final Future<List<String>> future;
  final void Function(String query, {required bool fromSuggestion, required String sourceContext}) onSelected;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: future,
      builder: (context, snapshot) {
        final suggestions = snapshot.data ?? const <String>[];
        if (snapshot.connectionState == ConnectionState.waiting && suggestions.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        return CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
              sliver: SliverList.list(
                children: <Widget>[
                  const _SearchIntroCard(),
                  const SizedBox(height: 18),
                  const Text(
                    'Popular in Prism',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Satoshi',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      for (final suggestion in suggestions)
                        _SuggestionChip(
                          label: suggestion,
                          onTap: () => onSelected(
                            suggestion,
                            fromSuggestion: true,
                            sourceContext: 'search_suggestion_chip',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchIntroCard extends StatelessWidget {
  const _SearchIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF13243A), Color(0xFF0E131B), Color(0xFF08090C)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x33000000),
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                'DISCOVER FASTER',
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Satoshi',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Pull up exactly what you want.',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Satoshi',
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Search regular wallpapers, matching pairs, 3D Spatial previews, and profile pictures from one place.',
            style: TextStyle(
              color: Colors.white70,
              fontFamily: 'Satoshi',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.32,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101217),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Satoshi',
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
