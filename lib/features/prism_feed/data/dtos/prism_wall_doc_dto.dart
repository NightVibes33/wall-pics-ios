import 'package:Prism/core/remote_store/converters/remote_store_json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'prism_wall_doc_dto.freezed.dart';
part 'prism_wall_doc_dto.g.dart';

@freezed
abstract class PrismWallDocDto with _$PrismWallDocDto {
  const factory PrismWallDocDto({
    @RemoteStoreStringConverter() @Default('') String id,
    @JsonKey(name: 'wallpaper_url') @RemoteStoreStringConverter() @Default('') String wallpaperUrl,
    @JsonKey(name: 'wallpaper_thumb') @RemoteStoreStringConverter() @Default('') String wallpaperThumb,
    @JsonKey(name: 'wallpaper_provider') @RemoteStoreStringConverter() @Default('') String wallpaperProvider,
    @RemoteStoreStringConverter() @Default('') String resolution,
    @JsonKey(name: 'file_size') int? fileSize,
    @RemoteStoreDateTimeConverter() DateTime? createdAt,
    @JsonKey(name: 'uploadedBy') @RemoteStoreStringConverter() @Default('') String uploadedBy,
    @RemoteStoreStringConverter() @Default('') String by,
    @RemoteStoreStringConverter() @Default('') String email,
    @JsonKey(name: 'userPhoto') @RemoteStoreStringConverter() @Default('') String userPhoto,
    @RemoteStoreStringConverter() @Default('') String desc,
    @RemoteStoreStringListConverter() @Default(<String>[]) List<String> collections,
    @RemoteStoreStringListConverter() @Default(<String>[]) List<String> tags,
    @Default(false) bool review,
    @JsonKey(name: 'aiMetadata')
    @RemoteStoreJsonMapConverter()
    @Default(<String, Object?>{})
    Map<String, Object?> aiMetadata,
    @JsonKey(name: 'is_streak_exclusive') @Default(false) bool isStreakExclusive,
    @JsonKey(name: 'required_streak_days') int? requiredStreakDays,
    @JsonKey(name: 'streak_shop_coin_cost') int? streakShopCoinCost,
  }) = _PrismWallDocDto;

  factory PrismWallDocDto.fromJson(Map<String, dynamic> json) => _$PrismWallDocDtoFromJson(json);
}
