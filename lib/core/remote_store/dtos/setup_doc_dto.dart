import 'package:Prism/core/remote_store/converters/remote_store_json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'setup_doc_dto.freezed.dart';
part 'setup_doc_dto.g.dart';

@freezed
abstract class SetupDocDto with _$SetupDocDto {
  const factory SetupDocDto({
    @RemoteStoreStringConverter() @Default('') String id,
    @RemoteStoreStringConverter() @Default('') String by,
    @RemoteStoreStringConverter() @Default('') String icon,
    @JsonKey(name: 'icon_url') @RemoteStoreStringConverter() @Default('') String iconUrl,
    @JsonKey(name: 'created_at') @RemoteStoreDateTimeConverter() DateTime? createdAt,
    @RemoteStoreStringConverter() @Default('') String desc,
    @RemoteStoreStringConverter() @Default('') String email,
    @RemoteStoreStringConverter() @Default('') String image,
    @RemoteStoreStringConverter() @Default('') String name,
    @RemoteStoreStringConverter() @Default('') String userPhoto,
    @JsonKey(name: 'wall_id') @RemoteStoreStringConverter() @Default('') String wallId,
    @JsonKey(name: 'wallpaper_provider') @RemoteStoreStringConverter() @Default('') String wallpaperProvider,
    @JsonKey(name: 'wallpaper_thumb') @RemoteStoreStringConverter() @Default('') String wallpaperThumb,
    @JsonKey(name: 'wallpaper_url') @RemoteStoreStringConverter() @Default('') String wallpaperUrl,
    @RemoteStoreStringConverter() @Default('') String widget,
    @RemoteStoreStringConverter() @Default('') String widget2,
    @JsonKey(name: 'widget_url') @RemoteStoreStringConverter() @Default('') String widgetUrl,
    @JsonKey(name: 'widget_url2') @RemoteStoreStringConverter() @Default('') String widgetUrl2,
    @RemoteStoreStringConverter() @Default('') String link,
    @Default(false) bool review,
    @RemoteStoreStringConverter() @Default('') String resolution,
    @RemoteStoreStringConverter() @Default('') String size,
  }) = _SetupDocDto;

  factory SetupDocDto.fromJson(Map<String, dynamic> json) => _$SetupDocDtoFromJson(json);
}
