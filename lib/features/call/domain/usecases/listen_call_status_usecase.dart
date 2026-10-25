import '../entities/call_session_entity.dart';
import '../repositories/call_repository.dart';

/// Live stream of status changes for one call, consumed by both caller and
/// callee sides of the future `CallCubit` (Phase 1 §11/§20).
class ListenCallStatusUseCase {
  final CallRepository repository;
  const ListenCallStatusUseCase(this.repository);

  Stream<CallSessionEntity> call(String callId) {
    return repository.watchCallStatus(callId);
  }
}
