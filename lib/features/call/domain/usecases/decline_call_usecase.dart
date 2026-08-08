import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/call_response.dart';
import '../repositories/call_repository.dart';

/// Callee declines a ringing call (Phase 1 §7/§13).
class DeclineCallUseCase {
  final CallRepository repository;
  const DeclineCallUseCase(this.repository);

  Future<Either<Failure, void>> call(String callId) {
    return repository.respondToCall(callId: callId, response: CallResponse.decline);
  }
}
