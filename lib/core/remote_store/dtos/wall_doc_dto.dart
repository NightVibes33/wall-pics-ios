import 'package:Prism/core/remote_store/converters/remote_store_json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'wall_doc_dto.freezed.dart';
part 'wall_doc_dto.g.dart';

@freezed
abstract class WallDocDto with _$WallDocDto {
  const factory WallDocDto({
    @RemoteStoreStringConverter() @Default('') String id,
    @RemoteStoreStringConverter() @Default('') String by,
    @RemoteStoreStringConverter() @Default('') String desc,
    @RemoteStoreStringConverter() @Default('') String size,
    @RemoteStoreStringConverter() @Default('') String resolution,
    @RemoteStoreStringConverter() @Default('') String email,
    @JsonKey(name: 'wallpaper_provider') @RemoteStoreStringConverter() @Default('') String wallpaperProvider,
    @JsonKey(name: 'wallpaper_thumb') @RemoteStoreStringConverter() @Default('') String wallpaperThumb,
    @JsonKey(name: 'wallpaper_url') @RemoteStoreStringConverter() @Default('') String wallpaperUrl,
    @RemoteStoreStringListConverter() @Default(<String>[]) List<String> collections,
    @RemoteStoreDateTimeConverter() DateTime? createdAt,
    @Default(false) bool review,
  }) = _WallDocDto;

  factory WallDocDto.fromJson(Map<String, dynamic> json) => _$WallDocDtoFromJson(json);
}

@freezed
abstract class FavouriteWallDocDto with _$FavouriteWallDocDto {
  const factory FavouriteWallDocDto({
    @RemoteStoreStringConverter() @Default('') String id,
    @RemoteStoreStringConverter() @Default('') String provider,
    @RemoteStoreStringConverter() @Default('') String url,
    @RemoteStoreStringConverter() @Default('') String thumb,
    @RemoteStoreStringConverter() @Default('') String category,
    @RemoteStoreStringConverter() @Default('') String views,
    @RemoteStoreStringConverter() @Default('') String resolution,
    @RemoteStoreStringConverter() @Default('') String fav,
    @RemoteStoreStringConverter() @Default('') String size,
    @RemoteStoreStringConverter() @Default('') String photographer,
    @RemoteStoreStringListConverter() @Default(<String>[]) List<String> collections,
    @RemoteStoreDateTimeConverter() DateTime? createdAt,
  }) = _FavouriteWallDocDto;

  factory FavouriteWallDocDto.fromJson(Map<String, dynamic> json) => _$FavouriteWallDocDtoFromJson(json);
}
