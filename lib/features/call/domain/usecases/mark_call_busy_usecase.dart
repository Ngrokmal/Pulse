import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/call_response.dart';
import '../repositories/call_repository.dart';

/// Callee is already on another live call — checked client-side on
/// incoming-call receipt, and re-validated server-side (Phase 1 §12/§21).
class MarkCallBusyUseCase {
  final CallRepository repository;
  const MarkCallBusyUseCase(this.repository);

  Future<Either<Failure, void>> call(String callId) {
    return repository.respondToCall(callId: callId, response: CallResponse.busy);
  }
}
