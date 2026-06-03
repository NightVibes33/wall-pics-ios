import 'dart:async';

import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/features/user_search/views/widgets/search_grid.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
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
  static const _screenColor = Color(0xFF050506);
  static const _fieldColor = Color(0xFF111114);

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
    for (final category in categories.take(80)) {
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
      appBar: AppBar(
        toolbarHeight: 78,
        backgroundColor: _screenColor,
        elevation: 0,
        surfaceTintColor: _screenColor,
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 64 : 0,
        leading: canPop
            ? Padding(
                padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
                child: Material(
                  color: _fieldColor,
                  borderRadius: BorderRadius.circular(18),
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              )
            : null,
        titleSpacing: canPop ? 0 : 16,
        title: Padding(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 4),
          child: _SearchField(
            controller: _searchController,
            isSubmitted: _isSubmitted,
            onChanged: (text) {
              if (text.trim().isEmpty && _isSubmitted) {
                _clearSearch();
              }
            },
            onClear: _clearSearch,
            onSubmit: (text, sourceContext) => _submitSearch(text, fromSuggestion: false, sourceContext: sourceContext),
          ),
        ),
      ),
      body: _isSubmitted ? SearchGrid(query: _submittedQuery) : _SearchSuggestions(future: _suggestionsFuture, onSelected: _submitSearch),
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
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        keyboardAppearance: Brightness.dark,
        cursorColor: Colors.white,
        style: const TextStyle(
          fontFamily: 'Satoshi',
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (text) => onSubmit(text, 'search_textfield'),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.only(top: 15, bottom: 14),
          border: InputBorder.none,
          disabledBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Icon(JamIcons.search, color: Colors.white, size: 25),
          hintText: 'Search Prism',
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.38),
          ),
          suffixIcon: IconButton(
            tooltip: isSubmitted ? 'Clear search' : 'Search',
            icon: Icon(isSubmitted ? Icons.close : JamIcons.search, color: Colors.white, size: isSubmitted ? 22 : 24),
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
        final suggestions = (snapshot.data ?? const <String>[]).take(64).toList(growable: false);
        if (snapshot.connectionState == ConnectionState.waiting && suggestions.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Popular',
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final suggestion in suggestions)
                          _SearchSuggestionChip(
                            label: suggestion,
                            onPressed: () => onSelected(suggestion, fromSuggestion: true, sourceContext: 'search_suggestion'),
                          ),
                      ],
                    ),
                    if (suggestions.isEmpty)
                      const SizedBox(
                        height: 160,
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchSuggestionChip extends StatelessWidget {
  const _SearchSuggestionChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF111114),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(JamIcons.search, color: Colors.white.withValues(alpha: 0.64), size: 16),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
