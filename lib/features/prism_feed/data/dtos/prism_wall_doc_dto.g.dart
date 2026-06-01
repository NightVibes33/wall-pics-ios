// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prism_wall_doc_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PrismWallDocDto _$PrismWallDocDtoFromJson(Map<String, dynamic> json) => _PrismWallDocDto(
  id: json['id'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['id']),
  wallpaperUrl: json['wallpaper_url'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['wallpaper_url']),
  wallpaperThumb: json['wallpaper_thumb'] == null
      ? ''
      : const RemoteStoreStringConverter().fromJson(json['wallpaper_thumb']),
  wallpaperProvider: json['wallpaper_provider'] == null
      ? ''
      : const RemoteStoreStringConverter().fromJson(json['wallpaper_provider']),
  resolution: json['resolution'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['resolution']),
  fileSize: (json['file_size'] as num?)?.toInt(),
  createdAt: const RemoteStoreDateTimeConverter().fromJson(json['createdAt']),
  uploadedBy: json['uploadedBy'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['uploadedBy']),
  by: json['by'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['by']),
  email: json['email'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['email']),
  userPhoto: json['userPhoto'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['userPhoto']),
  desc: json['desc'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['desc']),
  collections: json['collections'] == null
      ? const <String>[]
      : const RemoteStoreStringListConverter().fromJson(json['collections']),
  tags: json['tags'] == null ? const <String>[] : const RemoteStoreStringListConverter().fromJson(json['tags']),
  review: json['review'] as bool? ?? false,
  aiMetadata: json['aiMetadata'] == null
      ? const <String, Object?>{}
      : const RemoteStoreJsonMapConverter().fromJson(json['aiMetadata']),
  isStreakExclusive: json['is_streak_exclusive'] as bool? ?? false,
  requiredStreakDays: (json['required_streak_days'] as num?)?.toInt(),
  streakShopCoinCost: (json['streak_shop_coin_cost'] as num?)?.toInt(),
);

Map<String, dynamic> _$PrismWallDocDtoToJson(_PrismWallDocDto instance) => <String, dynamic>{
  'id': const RemoteStoreStringConverter().toJson(instance.id),
  'wallpaper_url': const RemoteStoreStringConverter().toJson(instance.wallpaperUrl),
  'wallpaper_thumb': const RemoteStoreStringConverter().toJson(instance.wallpaperThumb),
  'wallpaper_provider': const RemoteStoreStringConverter().toJson(instance.wallpaperProvider),
  'resolution': const RemoteStoreStringConverter().toJson(instance.resolution),
  'file_size': instance.fileSize,
  'createdAt': const RemoteStoreDateTimeConverter().toJson(instance.createdAt),
  'uploadedBy': const RemoteStoreStringConverter().toJson(instance.uploadedBy),
  'by': const RemoteStoreStringConverter().toJson(instance.by),
  'email': const RemoteStoreStringConverter().toJson(instance.email),
  'userPhoto': const RemoteStoreStringConverter().toJson(instance.userPhoto),
  'desc': const RemoteStoreStringConverter().toJson(instance.desc),
  'collections': const RemoteStoreStringListConverter().toJson(instance.collections),
  'tags': const RemoteStoreStringListConverter().toJson(instance.tags),
  'review': instance.review,
  'aiMetadata': const RemoteStoreJsonMapConverter().toJson(instance.aiMetadata),
  'is_streak_exclusive': instance.isStreakExclusive,
  'required_streak_days': instance.requiredStreakDays,
  'streak_shop_coin_cost': instance.streakShopCoinCost,
};
