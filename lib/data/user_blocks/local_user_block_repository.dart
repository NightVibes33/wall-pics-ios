import 'dart:async';

import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/utils/result.dart';
import 'package:Prism/features/session/domain/repositories/session_repository.dart';
import 'package:Prism/features/user_blocks/domain/repositories/user_block_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: UserBlockRepository)
class LocalUserBlockRepository implements UserBlockRepository {
  LocalUserBlockRepository(SessionRepository _) {
    _controller.add(<String>{});
  }

  final StreamController<Set<String>> _controller = StreamController<Set<String>>.broadcast();

  @override
  bool get hasLoadedBlockedCreatorEmails => true;

  @override
  Set<String> get cachedBlockedCreatorEmails => const <String>{};

  @override
  Stream<Set<String>> watchBlockedCreatorEmails() => _controller.stream;

  @override
  Future<Set<String>> getBlockedCreatorEmails({bool waitForInitialLoad = false}) async => const <String>{};

  @override
  Future<Result<List<BlockedUserListRow>>> fetchBlockedUsersList() async => Result.success(<BlockedUserListRow>[]);

  @override
  Future<Result<void>> blockUser({required String targetUserId}) async {
    if (targetUserId.trim().isEmpty) {
      return Result.error(const ValidationFailure('Invalid user.'));
    }
    return Result.error(const ServerFailure('Blocking users is unavailable in this build.'));
  }

  @override
  Future<Result<void>> unblockUser({required String targetUserId}) async {
    if (targetUserId.trim().isEmpty) {
      return Result.error(const ValidationFailure('Invalid user.'));
    }
    return Result.error(const ServerFailure('Blocking users is unavailable in this build.'));
  }
}
