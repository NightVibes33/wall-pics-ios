import 'package:Prism/core/persistence/data_sources/settings_local_data_source.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/data/categories/categories.dart';
import 'package:Prism/data/categories/category_definition.dart';

class PersonalizedInterest {
  const PersonalizedInterest({
    required this.name,
    required this.query,
    required this.imageUrl,
    required this.sources,
    this.catalogSlug,
    this.catalogContentType,
  });

  final String name;
  final String query;
  final String imageUrl;
  final List<WallpaperSource> sources;
  final String? catalogSlug;
  final String? catalogContentType;

  bool supports(WallpaperSource source) => sources.contains(source);
}

class PersonalizedInterestsCatalog {
  const PersonalizedInterestsCatalog._();

  static const List<String> _preferredDefaultNames = <String>[
    'Aesthetic',
    'Anime',
    'Gaming',
    'Nature',
  ];

  static final List<CategoryDefinition> _appInterestCategories = _buildAppInterestCategories();

  static Future<List<PersonalizedInterest>> load({
    required SettingsLocalDataSource settingsLocal,
  }) async {
    return _appInterestCategories
        .map(
          (category) => PersonalizedInterest(
            name: normalizeInterestName(category.name),
            query: _queryForCategory(category),
            imageUrl: '',
            sources: const <WallpaperSource>[WallpaperSource.wallhaven, WallpaperSource.pexels],
            catalogSlug: category.catalogSlug,
            catalogContentType: category.catalogContentType,
          ),
        )
        .toList(growable: false);
  }

  static List<String> selectedFromLocal(SettingsLocalDataSource settingsLocal) {
    final raw = settingsLocal.get<String>('onboarding_v2_interests', defaultValue: '');
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList(growable: false);
  }

  static List<String> sanitizeSelection(Iterable<String> values, List<PersonalizedInterest> catalog) {
    final valid = catalog.map((entry) => entry.name.toLowerCase()).toSet();
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && valid.contains(value.toLowerCase()))
        .toSet()
        .toList(growable: false);
  }

  static List<String> defaultSelection(List<PersonalizedInterest> catalog) {
    if (catalog.isEmpty) {
      return const <String>['Aesthetic', 'Anime', 'Gaming', 'Nature'];
    }
    final byName = <String, PersonalizedInterest>{for (final entry in catalog) entry.name.toLowerCase(): entry};
    final defaults = <String>[];
    for (final preferred in _preferredDefaultNames) {
      final match = byName[preferred.toLowerCase()];
      if (match != null) {
        defaults.add(match.name);
      }
    }
    if (defaults.length >= 4) {
      return defaults.take(4).toList(growable: false);
    }
    for (final entry in catalog) {
      if (defaults.contains(entry.name)) {
        continue;
      }
      defaults.add(entry.name);
      if (defaults.length >= 4) {
        break;
      }
    }
    return defaults;
  }

  static List<CategoryDefinition> appCategoryDefinitions() => List<CategoryDefinition>.unmodifiable(_appInterestCategories);

  static String normalizeInterestName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9 &]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? raw.trim() : cleaned;
  }

  static List<CategoryDefinition> _buildAppInterestCategories() {
    const excludedSlugs = <String>{'for-you', 'new', 'newest'};
    final seen = <String>{};
    final categories = <CategoryDefinition>[];
    for (final category in categoryDefinitions) {
      final slug = (category.catalogSlug ?? '').trim();
      final contentType = (category.catalogContentType ?? '').trim();
      if (slug.isEmpty || contentType != 'regular_wallpaper' || excludedSlugs.contains(slug)) {
        continue;
      }
      final normalizedName = normalizeInterestName(category.name);
      if (normalizedName.isEmpty || !seen.add(normalizedName.toLowerCase())) {
        continue;
      }
      categories.add(category);
    }
    return categories;
  }

  static String _queryForCategory(CategoryDefinition category) {
    final normalizedName = normalizeInterestName(category.name).trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName.toLowerCase();
    }
    final slug = (category.catalogSlug ?? '').trim();
    return slug
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAll(RegExp(r'[0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }
}
