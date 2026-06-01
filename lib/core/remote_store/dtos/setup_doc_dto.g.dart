// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'setup_doc_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SetupDocDto _$SetupDocDtoFromJson(Map<String, dynamic> json) => _SetupDocDto(
  id: json['id'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['id']),
  by: json['by'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['by']),
  icon: json['icon'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['icon']),
  iconUrl: json['icon_url'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['icon_url']),
  createdAt: const RemoteStoreDateTimeConverter().fromJson(json['created_at']),
  desc: json['desc'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['desc']),
  email: json['email'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['email']),
  image: json['image'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['image']),
  name: json['name'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['name']),
  userPhoto: json['userPhoto'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['userPhoto']),
  wallId: json['wall_id'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['wall_id']),
  wallpaperProvider: json['wallpaper_provider'] == null
      ? ''
      : const RemoteStoreStringConverter().fromJson(json['wallpaper_provider']),
  wallpaperThumb: json['wallpaper_thumb'] == null
      ? ''
      : const RemoteStoreStringConverter().fromJson(json['wallpaper_thumb']),
  wallpaperUrl: json['wallpaper_url'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['wallpaper_url']),
  widget: json['widget'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['widget']),
  widget2: json['widget2'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['widget2']),
  widgetUrl: json['widget_url'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['widget_url']),
  widgetUrl2: json['widget_url2'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['widget_url2']),
  link: json['link'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['link']),
  review: json['review'] as bool? ?? false,
  resolution: json['resolution'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['resolution']),
  size: json['size'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['size']),
);

Map<String, dynamic> _$SetupDocDtoToJson(_SetupDocDto instance) => <String, dynamic>{
  'id': const RemoteStoreStringConverter().toJson(instance.id),
  'by': const RemoteStoreStringConverter().toJson(instance.by),
  'icon': const RemoteStoreStringConverter().toJson(instance.icon),
  'icon_url': const RemoteStoreStringConverter().toJson(instance.iconUrl),
  'created_at': const RemoteStoreDateTimeConverter().toJson(instance.createdAt),
  'desc': const RemoteStoreStringConverter().toJson(instance.desc),
  'email': const RemoteStoreStringConverter().toJson(instance.email),
  'image': const RemoteStoreStringConverter().toJson(instance.image),
  'name': const RemoteStoreStringConverter().toJson(instance.name),
  'userPhoto': const RemoteStoreStringConverter().toJson(instance.userPhoto),
  'wall_id': const RemoteStoreStringConverter().toJson(instance.wallId),
  'wallpaper_provider': const RemoteStoreStringConverter().toJson(instance.wallpaperProvider),
  'wallpaper_thumb': const RemoteStoreStringConverter().toJson(instance.wallpaperThumb),
  'wallpaper_url': const RemoteStoreStringConverter().toJson(instance.wallpaperUrl),
  'widget': const RemoteStoreStringConverter().toJson(instance.widget),
  'widget2': const RemoteStoreStringConverter().toJson(instance.widget2),
  'widget_url': const RemoteStoreStringConverter().toJson(instance.widgetUrl),
  'widget_url2': const RemoteStoreStringConverter().toJson(instance.widgetUrl2),
  'link': const RemoteStoreStringConverter().toJson(instance.link),
  'review': instance.review,
  'resolution': const RemoteStoreStringConverter().toJson(instance.resolution),
  'size': const RemoteStoreStringConverter().toJson(instance.size),
};
