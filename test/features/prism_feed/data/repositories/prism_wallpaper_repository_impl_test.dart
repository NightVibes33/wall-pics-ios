import 'package:Prism/features/prism_feed/data/repositories/prism_wallpaper_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streak shop returns no wallpapers because the feature is not part of the wallpaper catalog', () async {
    final repository = PrismWallpaperRepositoryImpl(null, null, null);

    final result = await repository.fetchStreakShopWallpapers();

    expect(result.isSuccess, isTrue);
    expect(result.data, isEmpty);
    expect(repository.hasMore, isFalse);
  });
}
