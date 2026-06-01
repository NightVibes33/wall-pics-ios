// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_user_doc_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PublicUserDocDto _$PublicUserDocDtoFromJson(Map<String, dynamic> json) => _PublicUserDocDto(
  id: json['id'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['id']),
  name: json['name'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['name']),
  email: json['email'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['email']),
  username: json['username'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['username']),
  profilePhoto: json['profilePhoto'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['profilePhoto']),
  bio: json['bio'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['bio']),
  followers: json['followers'] == null
      ? const <String>[]
      : const RemoteStoreStringListConverter().fromJson(json['followers']),
  following: json['following'] == null
      ? const <String>[]
      : const RemoteStoreStringListConverter().fromJson(json['following']),
  links: json['links'] == null ? const <String, String>{} : const RemoteStoreStringMapConverter().fromJson(json['links']),
  premium: json['premium'] as bool? ?? false,
  coverPhoto: json['coverPhoto'] == null ? '' : const RemoteStoreStringConverter().fromJson(json['coverPhoto']),
);

Map<String, dynamic> _$PublicUserDocDtoToJson(_PublicUserDocDto instance) => <String, dynamic>{
  'id': const RemoteStoreStringConverter().toJson(instance.id),
  'name': const RemoteStoreStringConverter().toJson(instance.name),
  'email': const RemoteStoreStringConverter().toJson(instance.email),
  'username': const RemoteStoreStringConverter().toJson(instance.username),
  'profilePhoto': const RemoteStoreStringConverter().toJson(instance.profilePhoto),
  'bio': const RemoteStoreStringConverter().toJson(instance.bio),
  'followers': const RemoteStoreStringListConverter().toJson(instance.followers),
  'following': const RemoteStoreStringListConverter().toJson(instance.following),
  'links': const RemoteStoreStringMapConverter().toJson(instance.links),
  'premium': instance.premium,
  'coverPhoto': const RemoteStoreStringConverter().toJson(instance.coverPhoto),
};
