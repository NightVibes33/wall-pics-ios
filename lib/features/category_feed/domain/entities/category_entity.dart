import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/data/categories/category_definition.dart';

class CategoryEntity {
  const CategoryEntity({
    required this.name,
    required this.source,
    required this.searchType,
    required this.image,
    required this.image2,
    this.wallpicsSlug,
    this.wallpicsContentType,
  });

  final String name;
  final WallpaperSource source;
  final CategorySearchType searchType;
  final String image;
  final String image2;
  final String? wallpicsSlug;
  final String? wallpicsContentType;
}
