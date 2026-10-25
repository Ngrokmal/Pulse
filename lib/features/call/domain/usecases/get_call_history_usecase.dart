import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/call_history_page_entity.dart';
import '../repositories/call_repository.dart';

/// Cursor-paginated call history (Phase 1 §16, Open Decision #8 —
/// in-scope for this build).
class GetCallHistoryUseCase {
  final CallRepository repository;
  const GetCallHistoryUseCase(this.repository);

  Future<Either<Failure, CallHistoryPageEntity>> call({
    required String userId,
    String? cursor,
    int limit = 20,
  }) {
    return repository.getCallHistory(userId: userId, cursor: cursor, limit: limit);
  }
}
