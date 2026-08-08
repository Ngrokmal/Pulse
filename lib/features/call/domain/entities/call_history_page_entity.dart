import 'call_session_entity.dart';

/// One cursor-paginated page of Call History (Phase 1 §16, confirmed
/// in-scope per Open Decision #8).
class CallHistoryPageEntity {
  final List<CallSessionEntity> items;
  final String? nextCursor;

  const CallHistoryPageEntity({
    required this.items,
    this.nextCursor,
  });

  bool get hasMore => nextCursor != null;
}
