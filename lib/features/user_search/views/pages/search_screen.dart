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
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final Future<List<String>> _suggestionsFuture;
  String _submittedQuery = '';

  bool get _isSubmitted => _submittedQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = _loadSuggestions();
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
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        surfaceTintColor: Theme.of(context).primaryColor,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 6),
          child: TextField(
            cursorColor: Theme.of(context).colorScheme.error,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Satoshi',
                  color: Theme.of(context).colorScheme.secondary,
                ),
            controller: _searchController,
            onChanged: (text) {
              if (text.trim().isEmpty && _isSubmitted) {
                _clearSearch();
              }
            },
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.only(left: 24, top: 12),
              border: InputBorder.none,
              disabledBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Search Prism',
              hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: 'Satoshi',
                    color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.68),
                  ),
              suffixIcon: IconButton(
                tooltip: _isSubmitted ? 'Clear search' : 'Search',
                icon: Icon(_isSubmitted ? Icons.close : JamIcons.search, color: Theme.of(context).colorScheme.secondary),
                onPressed: _isSubmitted ? _clearSearch : () => _submitSearch(_searchController.text, fromSuggestion: false, sourceContext: 'search_icon'),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (text) => _submitSearch(text, fromSuggestion: false, sourceContext: 'search_textfield'),
          ),
        ),
      ),
      body: _isSubmitted ? SearchGrid(query: _submittedQuery) : _SearchSuggestions(future: _suggestionsFuture, onSelected: _submitSearch),
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
          return const Center(child: CircularProgressIndicator());
        }
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final suggestion in suggestions)
                      ActionChip(
                        label: Text(suggestion, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => onSelected(suggestion, fromSuggestion: true, sourceContext: 'search_suggestion'),
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
