import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/call_repository.dart';

/// Caller cancels a call still in 'ringing' before it's answered
/// (Phase 1 §7/§11).
class CancelCallUseCase {
  final CallRepository repository;
  const CancelCallUseCase(this.repository);

  Future<Either<Failure, void>> call(String callId) {
    return repository.cancelCall(callId);
  }
}
