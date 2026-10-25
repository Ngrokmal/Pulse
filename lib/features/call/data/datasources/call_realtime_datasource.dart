import '../dto/call_session_dto.dart';

/// Contract for Postgres Changes subscriptions on `call_sessions`
/// (Phase 1 §20). INTERFACE ONLY for this milestone — no Supabase import
/// here; the concrete implementation is deferred to the Data Layer
/// milestone, and will follow the existing per-feature
/// `supabase.channel('<x>_<id>')` convention.
abstract class CallRealtimeDataSource {
  /// Filtered `callee_id = userId AND status = 'ringing'`.
  Stream<CallSessionDto> subscribeToIncomingCalls(String userId);

  /// Filtered `id = callId`.
  Stream<CallSessionDto> subscribeToCallStatus(String callId);

  /// Explicit teardown, paired with every subscribe call per Phase 1 §20/§21
  /// to avoid the stale-channel regression risk already flagged.
  Future<void> unsubscribe(String channelKey);
}
