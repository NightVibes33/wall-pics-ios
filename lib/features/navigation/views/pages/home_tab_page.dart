import 'package:Prism/core/utils/status.dart';
import 'package:Prism/core/widgets/home/wallpapers/loading.dart';
import 'package:Prism/features/category_feed/biz/bloc/category_feed_bloc.j.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/category_feed/views/widgets/wallpaper_grid.dart';
import 'package:Prism/features/navigation/views/widgets/offline_banner.dart';
import 'package:Prism/features/navigation/views/widgets/prism_top_app_bar.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

@RoutePage()
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key});

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  bool _hasConnection = true;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final result = await InternetConnectionChecker.instance.hasConnection;
    if (mounted) {
      setState(() => _hasConnection = result);
    }
  }

  void _selectCategory(CategoryEntity category) {
    context.read<CategoryFeedBloc>().add(CategoryFeedEvent.categorySelected(category: category));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      appBar: const PrismTopAppBar(),
      body: Stack(
        children: <Widget>[
          BlocBuilder<CategoryFeedBloc, CategoryFeedState>(
            builder: (context, state) {
              if (state.status == LoadStatus.initial || (state.status == LoadStatus.loading && state.categories.isEmpty)) {
                return const LoadingCards();
              }
              if (state.status == LoadStatus.failure && state.items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async => context.read<CategoryFeedBloc>().add(const CategoryFeedEvent.started()),
                  child: ListView(
                    children: const [
                      SizedBox(height: 220),
                      Center(child: Text("Can't load Prism.")),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CategoryStrip(
                    categories: state.categories,
                    selected: state.selectedCategory,
                    onSelected: _selectCategory,
                  ),
                  const Expanded(child: WallpaperGrid()),
                ],
              );
            },
          ),
          if (!_hasConnection) ConnectivityWidget(),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.categories, required this.selected, required this.onSelected});

  final List<CategoryEntity> categories;
  final CategoryEntity? selected;
  final ValueChanged<CategoryEntity> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = selected?.name == category.name && selected?.catalogContentType == category.catalogContentType;
          return ChoiceChip(
            label: Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: isSelected,
            selectedColor: scheme.secondary.withValues(alpha: 0.16),
            onSelected: (_) => onSelected(category),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: categories.length,
      ),
    );
  }
}
