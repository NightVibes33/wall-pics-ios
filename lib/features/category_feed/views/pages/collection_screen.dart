import 'package:Prism/core/router/app_router.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/features/category_feed/biz/bloc/category_feed_bloc.j.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/features/prism_catalog/data/prism_catalog_data_source.dart';
import 'package:Prism/features/prism_catalog/data/prism_seed_media_store.dart';
import 'package:Prism/features/prism_catalog/views/prism_seed_media_image.dart';
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
          return const Center(child: Loader());
        }
        if (state.status == LoadStatus.failure && state.categories.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => context.read<CategoryFeedBloc>().add(const CategoryFeedEvent.started()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 60, 18, 120),
              children: const <Widget>[
                SizedBox(height: 120),
                _CollectionStateCard(title: "Can't load Prism categories.", subtitle: 'Pull down to try again.'),
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
    const placeholder = ColoredBox(color: Color(0xFF0F1115));
    return FutureBuilder<String>(
      future: _previewFuture,
      builder: (context, snapshot) {
        final url = snapshot.data?.trim() ?? '';
        if (url.isEmpty) return placeholder;
        if (PrismSeedMediaStore.instance.hasUrlSync(url)) {
          return PrismSeedMediaImage(
            url: url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            placeholder: (_) => placeholder,
            errorWidget: (_) => placeholder,
          );
        }
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        final title = category.name.trim().isEmpty ? 'Prism' : category.name.trim();
        final imageUrl = category.image.trim().isNotEmpty ? category.image.trim() : category.image2.trim();
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: const Color(0xFF0D1015),
            child: InkWell(
              onTap: () {
                final encodedName = Uri.encodeComponent(
                  '${category.catalogContentType ?? ''}|${category.catalogSlug ?? ''}|${category.name}',
                );
                context.router.push(CollectionViewRoute(collectionName: 'category:$encodedName'));
              },
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _CategoryPreviewImage(category: category, fallbackImageUrl: imageUrl),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.9),
                          Colors.black.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                        stops: const <double>[0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Text(
                              'PRISM',
                              style: TextStyle(
                                color: Colors.white70,
                                fontFamily: 'Satoshi',
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Satoshi',
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Open collection',
                          style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Satoshi',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CollectionStateCard extends StatelessWidget {
  const _CollectionStateCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101217),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Satoshi',
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'Satoshi',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
