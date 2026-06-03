import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/features/category_feed/biz/bloc/category_feed_bloc.j.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CategoryFeedBloc, CategoryFeedState>(
      builder: (context, state) {
        if (state.status == LoadStatus.initial || (state.status == LoadStatus.loading && state.categories.isEmpty)) {
          return Center(child: Loader());
        }
        if (state.status == LoadStatus.failure && state.categories.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => context.read<CategoryFeedBloc>().add(const CategoryFeedEvent.started()),
            child: ListView(
              children: const [
                SizedBox(height: 220),
                Center(child: Text("Can't load Prism categories.")),
              ],
            ),
          );
        }
        return _PrismCategoryGrid(categories: state.categories);
      },
    );
  }
}

class _CategoryPreviewImage extends StatefulWidget {
  const _CategoryPreviewImage({required this.category, required this.fallbackImageUrl});

  final CategoryEntity category;
  final String fallbackImageUrl;

  @override
  State<_CategoryPreviewImage> createState() => _CategoryPreviewImageState();
}

class _CategoryPreviewImageState extends State<_CategoryPreviewImage> {
  late Future<String> _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _CategoryPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.catalogContentType != widget.category.catalogContentType ||
        oldWidget.category.catalogSlug != widget.category.catalogSlug ||
        oldWidget.fallbackImageUrl != widget.fallbackImageUrl) {
      _previewFuture = _loadPreview();
    }
  }

  Future<String> _loadPreview() async {
    final fallback = widget.fallbackImageUrl.trim();
    if (fallback.isNotEmpty) return fallback;
    return PrismCatalogDataSource.instance.categoryPreviewUrl(
      contentType: widget.category.catalogContentType?.trim() ?? '',
      slug: widget.category.catalogSlug?.trim() ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return FutureBuilder<String>(
      future: _previewFuture,
      builder: (context, snapshot) {
        final url = snapshot.data?.trim() ?? '';
        if (url.isEmpty) return placeholder;
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          filterQuality: FilterQuality.high,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
        );
      },
    );
  }
}

class _PrismCategoryGrid extends StatelessWidget {
  const _PrismCategoryGrid({required this.categories});

  final List<CategoryEntity> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 120),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        final title = category.name.trim().isEmpty ? 'Prism' : category.name.trim();
        final imageUrl = category.image.trim().isNotEmpty ? category.image.trim() : category.image2.trim();
        return Material(
          color: theme.colorScheme.surfaceContainer,
          child: InkWell(
            onTap: () {
              final encodedName = Uri.encodeComponent(
                '${category.catalogContentType ?? ''}|${category.catalogSlug ?? ''}|${category.name}',
              );
              context.router.push(CollectionViewRoute(collectionName: 'category:$encodedName'));
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _CategoryPreviewImage(category: category, fallbackImageUrl: imageUrl),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
