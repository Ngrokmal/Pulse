import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/agora_repository.dart';

/// Speaker/earpiece toggle (Phase 1 §6).
class ToggleSpeakerUseCase {
  final AgoraRepository repository;
  const ToggleSpeakerUseCase(this.repository);

  Future<Either<Failure, void>> call(bool enabled) {
    return repository.toggleSpeaker(enabled);
  }
}
