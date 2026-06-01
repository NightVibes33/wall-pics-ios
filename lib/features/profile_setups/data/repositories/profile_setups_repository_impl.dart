import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/remote_store/dtos/setup_doc_dto.dart';
import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/user_blocks/blocked_creators_filter.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/core/wallpaper/wallpaper_source.dart';
import 'package:Prism/features/profile_setups/domain/entities/profile_setup_entity.dart';
import 'package:Prism/features/profile_setups/domain/entities/profile_setups_page.dart';
import 'package:Prism/features/profile_setups/domain/repositories/profile_setups_repository.dart';
import 'package:Prism/features/user_blocks/domain/repositories/user_block_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ProfileSetupsRepository)
class ProfileSetupsRepositoryImpl implements ProfileSetupsRepository {
  ProfileSetupsRepositoryImpl(this._remoteStoreClient, this._userBlockRepository);

  final RemoteStoreClient _remoteStoreClient;
  final UserBlockRepository _userBlockRepository;
  final Map<String, String> _cursorByEmail = {};

  @override
  Future<Result<ProfileSetupsPage>> fetchProfileSetups({required String email, required bool refresh}) async {
    final Set<String> blocked = await _userBlockRepository.getBlockedCreatorEmails(waitForInitialLoad: true);
    if (BlockedCreatorsFilter.hidesCreatorEmail(email, blocked)) {
      return Result.success(const ProfileSetupsPage(items: <ProfileSetupEntity>[], hasMore: false, nextCursor: null));
    }
    try {
      final cursor = _cursorByEmail[email];
      final rows = await _remoteStoreClient.query<_SetupRow>(
        RemoteStoreQuerySpec(
          collection: RemoteCollections.setups,
          sourceTag: 'profile_setups.fetch',
          filters: <RemoteStoreFilter>[
            const RemoteStoreFilter(field: 'review', op: RemoteStoreFilterOp.isEqualTo, value: true),
            RemoteStoreFilter(field: 'email', op: RemoteStoreFilterOp.isEqualTo, value: email),
          ],
          orderBy: const <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'created_at', descending: true)],
          limit: 8,
          startAfterDocId: refresh ? null : cursor,
        ),
        (data, docId) => _SetupRow(docId: docId, doc: SetupDocDto.fromJson(data)),
      );
      if (rows.isNotEmpty) {
        _cursorByEmail[email] = rows.last.docId;
      }

      final items = rows.map((row) => _mapSetup(row.doc, row.docId)).toList(growable: false);

      return Result.success(
        ProfileSetupsPage(items: items, hasMore: rows.length == 8, nextCursor: _cursorByEmail[email]),
      );
    } catch (error) {
      return Result.error(ServerFailure('Unable to load profile setups: $error'));
    }
  }

  ProfileSetupEntity _mapSetup(SetupDocDto dto, String docId) {
    return ProfileSetupEntity(
      id: dto.id.isNotEmpty ? dto.id : docId,
      by: dto.by,
      icon: dto.icon,
      iconUrl: dto.iconUrl,
      createdAt: dto.createdAt,
      desc: dto.desc,
      email: dto.email,
      image: dto.image,
      name: dto.name,
      userPhoto: dto.userPhoto,
      wallId: dto.wallId,
      source: WallpaperSourceX.fromWire(dto.wallpaperProvider),
      wallpaperThumb: dto.wallpaperThumb,
      wallpaperUrl: dto.wallpaperUrl,
      widget: dto.widget,
      widget2: dto.widget2,
      widgetUrl: dto.widgetUrl,
      widgetUrl2: dto.widgetUrl2,
      link: dto.link,
      review: dto.review,
      resolution: dto.resolution,
      size: dto.size,
      remoteStoreDocumentId: docId,
    );
  }
}

class _SetupRow {
  const _SetupRow({required this.docId, required this.doc});

  final String docId;
  final SetupDocDto doc;
}
