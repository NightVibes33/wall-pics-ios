import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/data/categories/categories.dart' as category_data;
import 'package:Prism/data/categories/category_definition.dart';
import 'package:Prism/features/category_feed/biz/bloc/category_feed_bloc.j.dart';
import 'package:Prism/features/category_feed/domain/entities/category_entity.dart';
import 'package:Prism/global/categoryMenu.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

CategoryMenu _toMenu(CategoryEntity category) => CategoryMenu(
  name: category.name,
  provider: category.source.legacyProviderString,
  image: category.image,
  image2: category.image2,
  catalogSlug: category.catalogSlug,
  catalogContentType: category.catalogContentType,
);

CategoryEntity _toEntity(CategoryMenu choice, List<CategoryEntity> categories) {
  final selectedName = (choice.name ?? '').trim();
  final selectedSlug = (choice.catalogSlug ?? '').trim();
  final selectedType = (choice.catalogContentType ?? '').trim();
  for (final category in categories) {
    if (selectedSlug.isNotEmpty && selectedType.isNotEmpty) {
      if (category.catalogSlug == selectedSlug && category.catalogContentType == selectedType) {
        return category;
      }
      continue;
    }
    if (category.name == selectedName) {
      return category;
    }
  }
  return CategoryEntity(
    name: choice.name ?? '',
    source: WallpaperSourceX.fromWire(choice.provider),
    searchType: CategorySearchType.search,
    image: choice.image ?? '',
    image2: choice.image2 ?? '',
    catalogSlug: choice.catalogSlug,
    catalogContentType: choice.catalogContentType,
  );
}

final List<CategoryMenu> categoryChoices = category_data.categoryDefinitions
    .map(
      (def) => CategoryMenu(
        name: def.name,
        provider: def.source.legacyProviderString,
        image: def.imageUrl,
        image2: def.secondaryImageUrl,
        catalogSlug: def.catalogSlug,
        catalogContentType: def.catalogContentType,
      ),
    )
    .toList(growable: false);

extension CategoryFeedBlocAdapterX on BuildContext {
  CategoryFeedBloc _categoryFeedBloc(bool listen) => listen ? watch<CategoryFeedBloc>() : read<CategoryFeedBloc>();

  List<CategoryMenu> categoryChoiceList({bool listen = true}) {
    final categories = _categoryFeedBloc(listen).state.categories;
    if (categories.isEmpty) {
      return categoryChoices;
    }
    return categories.map(_toMenu).toList(growable: false);
  }

  CategoryMenu categorySelectedChoice({bool listen = true}) {
    final state = _categoryFeedBloc(listen).state;
    final selected = state.selectedCategory;
    if (selected == null) {
      return categoryChoiceList(listen: listen).first;
    }
    return _toMenu(selected);
  }

  String? categoryCurrentChoice({bool listen = true}) => categorySelectedChoice(listen: listen).name;

  Future<void> categoryChangeWallpaperFuture(CategoryMenu choice, String mode) async {
    final bloc = _categoryFeedBloc(false);
    final category = _toEntity(choice, bloc.state.categories);
    if (mode == 'r') {
      bloc.add(CategoryFeedEvent.categorySelected(category: category));
    } else {
      final current = bloc.state.selectedCategory;
      final sameCatalogCategory = current != null &&
          (current.catalogSlug ?? '').isNotEmpty &&
          (current.catalogContentType ?? '').isNotEmpty &&
          current.catalogSlug == category.catalogSlug &&
          current.catalogContentType == category.catalogContentType;
      final sameLegacyCategory = current != null &&
          (current.catalogSlug == null || current.catalogSlug!.isEmpty) &&
          current.name == category.name;
      if (!sameCatalogCategory && !sameLegacyCategory) {
        bloc.add(CategoryFeedEvent.categorySelected(category: category));
      } else {
        bloc.add(const CategoryFeedEvent.fetchMoreRequested());
      }
    }
  }
}
