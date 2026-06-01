import 'package:Prism/core/remote_store/converters/remote_store_json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'public_user_doc_dto.freezed.dart';
part 'public_user_doc_dto.g.dart';

@freezed
abstract class PublicUserDocDto with _$PublicUserDocDto {
  const factory PublicUserDocDto({
    @RemoteStoreStringConverter() @Default('') String id,
    @RemoteStoreStringConverter() @Default('') String name,
    @RemoteStoreStringConverter() @Default('') String email,
    @RemoteStoreStringConverter() @Default('') String username,
    @RemoteStoreStringConverter() @Default('') String profilePhoto,
    @RemoteStoreStringConverter() @Default('') String bio,
    @RemoteStoreStringListConverter() @Default(<String>[]) List<String> followers,
    @RemoteStoreStringListConverter() @Default(<String>[]) List<String> following,
    @RemoteStoreStringMapConverter() @Default(<String, String>{}) Map<String, String> links,
    @Default(false) bool premium,
    @RemoteStoreStringConverter() @Default('') String coverPhoto,
  }) = _PublicUserDocDto;

  factory PublicUserDocDto.fromJson(Map<String, dynamic> json) => _$PublicUserDocDtoFromJson(json);
}
