import '../entities/call_session_entity.dart';
import '../repositories/call_repository.dart';

/// Live stream of incoming ('ringing') calls for [userId] — powers the
/// future `IncomingCallListenerCubit` (Phase 1 §10/§20). Not itself a
/// Cubit; presentation layer is out of scope for this milestone.
class ListenIncomingCallUseCase {
  final CallRepository repository;
  const ListenIncomingCallUseCase(this.repository);

  Stream<CallSessionEntity> call(String userId) {
    return repository.watchIncomingCalls(userId);
  }
}
