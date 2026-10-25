import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/call_response.dart';
import '../repositories/call_repository.dart';

/// Callee accepts a ringing call (Phase 1 §7/§10).
class AcceptCallUseCase {
  final CallRepository repository;
  const AcceptCallUseCase(this.repository);

  Future<Either<Failure, void>> call(String callId) {
    return repository.respondToCall(callId: callId, response: CallResponse.accept);
  }
}
