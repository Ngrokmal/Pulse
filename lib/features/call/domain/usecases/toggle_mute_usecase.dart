import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/agora_repository.dart';

/// Local mute toggle — handled directly by the Agora engine, never
/// round-tripped through Supabase (Phase 1 §6).
class ToggleMuteUseCase {
  final AgoraRepository repository;
  const ToggleMuteUseCase(this.repository);

  Future<Either<Failure, void>> call(bool muted) {
    return repository.toggleMute(muted);
  }
}
