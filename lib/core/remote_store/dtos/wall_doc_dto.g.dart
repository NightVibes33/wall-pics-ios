// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wall_doc_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WallDocDto _$WallDocDtoFromJson(Map<String, dynamic> json) => _WallDocDto(
  id: json['id'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['id']),
  by: json['by'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['by']),
  desc: json['desc'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['desc']),
  size: json['size'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['size']),
  resolution: json['resolution'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['resolution']),
  email: json['email'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['email']),
  wallpaperProvider: json['wallpaper_provider'] == null
      ? ''
      : const RemoteStoreStringConverter().fromJson(json['wallpaper_provider']),
  wallpaperThumb: json['wallpaper_thumb'] == null
      ? ''
      : const RemoteStoreStringConverter().fromJson(json['wallpaper_thumb']),
  wallpaperUrl: json['wallpaper_url'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['wallpaper_url']),
  collections: json['collections'] == null
      ? const <String>[]
      : const RemoteStoreStringListConverter().fromJson(json['collections']),
  createdAt: const RemoteStoreDateTimeConverter().fromJson(json['createdAt']),
  review: json['review'] as bool? ?? false,
);

Map<String, dynamic> _$WallDocDtoToJson(_WallDocDto instance) => <String, dynamic>{
  'id': const RemoteStoreStringConverter().toJson(instance.id),
  'by': const RemoteStoreStringConverter().toJson(instance.by),
  'desc': const RemoteStoreStringConverter().toJson(instance.desc),
  'size': const RemoteStoreStringConverter().toJson(instance.size),
  'resolution': const RemoteStoreStringConverter().toJson(instance.resolution),
  'email': const RemoteStoreStringConverter().toJson(instance.email),
  'wallpaper_provider': const RemoteStoreStringConverter().toJson(instance.wallpaperProvider),
  'wallpaper_thumb': const RemoteStoreStringConverter().toJson(instance.wallpaperThumb),
  'wallpaper_url': const RemoteStoreStringConverter().toJson(instance.wallpaperUrl),
  'collections': const RemoteStoreStringListConverter().toJson(instance.collections),
  'createdAt': const RemoteStoreDateTimeConverter().toJson(instance.createdAt),
  'review': instance.review,
};

_FavouriteWallDocDto _$FavouriteWallDocDtoFromJson(Map<String, dynamic> json) => _FavouriteWallDocDto(
  id: json['id'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['id']),
  provider: json['provider'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['provider']),
  url: json['url'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['url']),
  thumb: json['thumb'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['thumb']),
  category: json['category'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['category']),
  views: json['views'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['views']),
  resolution: json['resolution'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['resolution']),
  fav: json['fav'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['fav']),
  size: json['size'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['size']),
  photographer: json['photographer'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['photographer']),
  collections: json['collections'] == null
      ? const <String>[]
      : const RemoteStoreStringListConverter().fromJson(json['collections']),
  createdAt: const RemoteStoreDateTimeConverter().fromJson(json['createdAt']),
);

Map<String, dynamic> _$FavouriteWallDocDtoToJson(_FavouriteWallDocDto instance) => <String, dynamic>{
  'id': const RemoteStoreStringConverter().toJson(instance.id),
  'provider': const RemoteStoreStringConverter().toJson(instance.provider),
  'url': const RemoteStoreStringConverter().toJson(instance.url),
  'thumb': const RemoteStoreStringConverter().toJson(instance.thumb),
  'category': const RemoteStoreStringConverter().toJson(instance.category),
  'views': const RemoteStoreStringConverter().toJson(instance.views),
  'resolution': const RemoteStoreStringConverter().toJson(instance.resolution),
  'fav': const RemoteStoreStringConverter().toJson(instance.fav),
  'size': const RemoteStoreStringConverter().toJson(instance.size),
  'photographer': const RemoteStoreStringConverter().toJson(instance.photographer),
  'collections': const RemoteStoreStringListConverter().toJson(instance.collections),
  'createdAt': const RemoteStoreDateTimeConverter().toJson(instance.createdAt),
};
