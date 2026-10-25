import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../domain/entities/friend_request_status.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/repositories/friend_repository.dart';
import '../datasources/friend_local_data_source.dart';
import '../../../home/domain/repositories/chat_list_repository.dart';
import '../../../chat/domain/repositories/chat_repository.dart';
import '../../../chat/domain/usecases/get_or_create_direct_chat_usecase.dart';

class FriendRepositoryImpl implements FriendRepository {
  final FriendLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final ChatListRepository chatListRepository;
  final GetOrCreateDirectChatUseCase getOrCreateDirectChatUseCase;

  final ChatRepository chatRepository;

  FriendRepositoryImpl({
    required this.localDataSource,
    required this.supabase,
    required this.chatListRepository,
    required this.getOrCreateDirectChatUseCase,
    required this.chatRepository,
  });

  String? _currentSupabaseUid() => supabase.auth.currentUser?.id;

  Future<String> _resolveUid(String firebaseUid) {
    return UserIdBridge.resolve(firebaseUid, currentSupabaseUserId: _currentSupabaseUid());
  }

  Future<String> _reverseResolve(String supabaseUid) async {
    return await UserIdBridge.reverseResolve(supabaseUid) ?? supabaseUid;
  }

  PostgrestFilterBuilder _pairFilter(PostgrestFilterBuilder query, String a, String b) {
    return query.or('and(requester_id.eq.$a,addressee_id.eq.$b),and(requester_id.eq.$b,addressee_id.eq.$a)');
  }


  @override
  Future<Either<Failure, FriendRequestStatus>> getFriendRequestStatus({
    required String viewerUid,
    required String profileUid,
  }) async {
    try {
      final viewer = await _resolveUid(viewerUid);
      final profile = await _resolveUid(profileUid);

      final rows = await _pairFilter(
        supabase.from('friendships').select('requester_id, status'),
        viewer,
        profile,
      ).limit(1);

      if (rows.isEmpty) return const Right(FriendRequestStatus.notFriends);

      final row = rows.first;
      final status = row['status'] as String? ?? 'pending';
      if (status == 'accepted') return const Right(FriendRequestStatus.friends);
      if (status == 'pending') {
        final requesterId = row['requester_id'] as String?;
        return Right(requesterId == viewer ? FriendRequestStatus.requestSent : FriendRequestStatus.requestReceived);
      }
      return const Right(FriendRequestStatus.notFriends);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> sendFriendRequest({required String fromUid, required String toUid}) async {
    if (fromUid == toUid) return const Right(null);
    try {
      final from = await _resolveUid(fromUid);
      final to = await _resolveUid(toUid);

      final blockedEitherDirection = await supabase
          .from('blocked_users')
          .select('blocker_id')
          .or('and(blocker_id.eq.$to,blocked_id.eq.$from),and(blocker_id.eq.$from,blocked_id.eq.$to)');
      if (blockedEitherDirection.isNotEmpty) {
        return const Left(FirebaseFailure('Unable to send friend request.'));
      }

      final privacyRaw = await supabase.rpc('get_friend_request_privacy', params: {'target_id': to}) as String?;
      final privacy = friendRequestPrivacyFromString(privacyRaw);
      if (privacy == FriendRequestPrivacy.nobody) {
        return const Left(FirebaseFailure('This user is not accepting friend requests.'));
      }
      if (privacy == FriendRequestPrivacy.friendsOfFriends) {
        final mutualResult = await getMutualFriendsCount(uid: fromUid, otherUid: toUid);
        final mutualCount = mutualResult.fold((_) => 0, (count) => count);
        if (mutualCount <= 0) {
          return const Left(FirebaseFailure('This user only accepts requests from friends of friends.'));
        }
      }

      final existing = await _pairFilter(
        supabase.from('friendships').select('status'),
        from,
        to,
      ).maybeSingle();
      if (existing != null) {
        return const Right(null);
      }

      await supabase.from('friendships').insert({
        'requester_id': from,
        'addressee_id': to,
        'status': 'pending',
      });
      return const Right(null);
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const Right(null);
      return Left(FirebaseFailure(e.message));
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> cancelFriendRequest({required String uid, required String targetUid}) async {
    try {
      final a = await _resolveUid(uid);
      final b = await _resolveUid(targetUid);
      await _pairFilter(supabase.from('friendships').delete(), a, b).eq('status', 'pending');
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> acceptFriendRequest({required String uid, required String requesterUid}) async {
    try {
      final addressee = await _resolveUid(uid);
      final requester = await _resolveUid(requesterUid);
      await supabase
          .from('friendships')
          .update({'status': 'accepted'})
          .eq('requester_id', requester)
          .eq('addressee_id', addressee)
          .eq('status', 'pending');
      chatListRepository.invalidateFriendIdsCache(addressee);

      try {
        await getOrCreateDirectChatUseCase.call(uidA: uid, uidB: requesterUid);

        final chatId = chatRepository.generateDirectChatId(uidA: uid, uidB: requesterUid);
        await chatRepository.touchDirectChat(chatId: chatId);
      } catch (_) {
      }

      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> rejectFriendRequest({required String uid, required String requesterUid}) async {
    try {
      final addressee = await _resolveUid(uid);
      final requester = await _resolveUid(requesterUid);
      await supabase
          .from('friendships')
          .delete()
          .eq('requester_id', requester)
          .eq('addressee_id', addressee)
          .eq('status', 'pending');
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }


  @override
  Future<Either<Failure, void>> unfriend({required String uid, required String targetUid}) async {
    try {
      final a = await _resolveUid(uid);
      final b = await _resolveUid(targetUid);
      await _pairFilter(supabase.from('friendships').delete(), a, b).eq('status', 'accepted');
      chatListRepository.invalidateFriendIdsCache(a);
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getFriends(String uid) async {
    try {
      final me = await _resolveUid(uid);
      final rows = await supabase
          .from('friendships')
          .select('requester_id, addressee_id')
          .or('requester_id.eq.$me,addressee_id.eq.$me')
          .eq('status', 'accepted');

      final ids = <String>[];
      for (final row in rows) {
        final requester = row['requester_id'] as String;
        final addressee = row['addressee_id'] as String;
        final counterpart = requester == me ? addressee : requester;
        ids.add(await _reverseResolve(counterpart));
      }
      return Right(ids);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  final Map<String, RealtimeChannel> _friendsChannels = {};

  @override
  Stream<List<String>> streamFriends(String uid) {
    final controller = StreamController<List<String>>();
    bool cancelled = false;
    String? myUuid;
    bool hasEmittedFriends = false;

    Future<void> runDelta() async {
      final selfUuid = myUuid;
      if (selfUuid == null) return;

      try {
        final cursor = await localDataSource.getFriendsSyncedAt(uid) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rows = await supabase
            .from('friendships')
            .select()
            .or('requester_id.eq.$selfUuid,addressee_id.eq.$selfUuid')
            .gt('updated_at', cursor.toUtc().toIso8601String())
            .order('updated_at');

        if (rows.isEmpty) return;

        DateTime latest = cursor;
        for (final row in rows) {
          final requester = row['requester_id'] as String;
          final addressee = row['addressee_id'] as String;
          final status = row['status'] as String? ?? 'pending';
          final counterpartSupabaseId = requester == selfUuid ? addressee : requester;
          final counterpartFirebaseId = await _reverseResolve(counterpartSupabaseId);

          await localDataSource.upsertFriendship(
            uid: uid,
            counterpartUid: counterpartFirebaseId,
            isAccepted: status == 'accepted',
          );

          final rawUpdatedAt = row['updated_at'];
          final updatedAt = rawUpdatedAt is String ? DateTime.parse(rawUpdatedAt).toLocal() : DateTime.now();
          if (updatedAt.isAfter(latest)) latest = updatedAt;
        }

        await localDataSource.setFriendsSyncedAt(uid, latest);
        if (!controller.isClosed) {
          hasEmittedFriends = true;
          controller.add(await localDataSource.getCachedFriendIds(uid));
        }
      } catch (e) {
        if (!hasEmittedFriends && !controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    Future<void> start() async {
      final cached = await localDataSource.getCachedFriendIds(uid);
      if (cached.isNotEmpty && !controller.isClosed) {
        hasEmittedFriends = true;
        controller.add(cached);
      }

      final String resolvedUuid;
      try {
        resolvedUuid = await _resolveUid(uid);
      } catch (_) {
        return;
      }
      if (cancelled) return;
      myUuid = resolvedUuid;

      final channel = supabase
          .channel('friends_$resolvedUuid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'friendships',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'requester_id', value: resolvedUuid),
            callback: (payload) => runDelta(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'friendships',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'addressee_id', value: resolvedUuid),
            callback: (payload) => runDelta(),
          );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) runDelta();
        if (error != null && !hasEmittedFriends && !controller.isClosed) controller.addError(error);
      });

      if (cancelled) {
        await supabase.removeChannel(channel);
        return;
      }

      final existing = _friendsChannels[resolvedUuid];
      if (existing != null) await supabase.removeChannel(existing);
      _friendsChannels[resolvedUuid] = channel;
    }

    start();

    controller.onCancel = () async {
      cancelled = true;
      final uuid = myUuid;
      if (uuid != null) {
        final channel = _friendsChannels[uuid];
        if (channel != null) {
          await supabase.removeChannel(channel);
          if (identical(_friendsChannels[uuid], channel)) {
            _friendsChannels.remove(uuid);
          }
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }


  @override
  Future<Either<Failure, void>> blockUser({required String uid, required String targetUid}) async {
    if (uid == targetUid) return const Right(null);
    try {
      final blocker = await _resolveUid(uid);
      final blocked = await _resolveUid(targetUid);

      await _pairFilter(supabase.from('friendships').delete(), blocker, blocked);

      await supabase.from('blocked_users').insert({'blocker_id': blocker, 'blocked_id': blocked});
      chatListRepository.invalidateFriendIdsCache(blocker);
      return const Right(null);
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const Right(null);
      return Left(FirebaseFailure(e.message));
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> unblockUser({required String uid, required String targetUid}) async {
    try {
      final blocker = await _resolveUid(uid);
      final blocked = await _resolveUid(targetUid);
      await supabase.from('blocked_users').delete().eq('blocker_id', blocker).eq('blocked_id', blocked);
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getBlockedUsers(String uid) async {
    try {
      final blocker = await _resolveUid(uid);
      final rows = await supabase.from('blocked_users').select('blocked_id').eq('blocker_id', blocker);
      final ids = <String>[];
      for (final row in rows) {
        ids.add(await _reverseResolve(row['blocked_id'] as String));
      }
      return Right(ids);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }


  @override
  Future<Either<Failure, int>> getMutualFriendsCount({required String uid, required String otherUid}) async {
    try {
      final a = await _resolveUid(uid);
      final b = await _resolveUid(otherUid);
      final result = await supabase.rpc('get_mutual_friends_count', params: {'a': a, 'b': b});
      return Right((result as num).toInt());
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<void> close() async {
    for (final channel in _friendsChannels.values) {
      await supabase.removeChannel(channel);
    }
    _friendsChannels.clear();
  }
}
