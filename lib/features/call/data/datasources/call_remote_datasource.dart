import '../dto/agora_token_dto.dart';
import '../dto/call_session_dto.dart';

/// Contract for CRUD access to `call_sessions`/`call_events` and the
/// `generate-agora-token` Edge Function. INTERFACE ONLY for this milestone
/// — no Supabase import here; the concrete implementation
/// (`CallRemoteDataSourceImpl`, using `PostgrestFilterBuilder`/
/// `functions.invoke`, mirroring `chat_repository_impl.dart`'s patterns)
/// is deferred to the Data Layer milestone, once schema/Edge Function work
/// is approved.
abstract class CallRemoteDataSource {
  Future<CallSessionDto> createCallSession({
    required String callerId,
    required String calleeId,
    required String channelName,
    required String callType,
    required int agoraUidCaller,
    required int agoraUidCallee,
  });

  Future<void> updateCallStatus({
    required String callId,
    required String status,
    String? endReason,
  });

  Future<CallSessionDto?> getCallSession(String callId);

  Future<List<CallSessionDto>> getCallHistory({
    required String userId,
    String? cursor,
    int limit = 20,
  });

  Future<void> insertCallEvent({
    required String callId,
    required String eventType,
    String? actorId,
    Map<String, dynamic>? metadata,
  });

  Future<AgoraTokenDto> fetchAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  });
}
