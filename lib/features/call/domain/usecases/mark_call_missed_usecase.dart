import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/call_repository.dart';

/// Fired by the caller-side ringing timeout (Phase 1 §14/§15), or by the
/// defensive stale-row reconciliation on next app open.
class MarkCallMissedUseCase {
  final CallRepository repository;
  const MarkCallMissedUseCase(this.repository);

  Future<Either<Failure, void>> call(String callId) {
    return repository.markMissed(callId);
  }
}
