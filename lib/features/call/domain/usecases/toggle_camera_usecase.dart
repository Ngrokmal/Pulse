import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/agora_repository.dart';

/// Local camera on/off toggle (Phase 1 §6).
class ToggleCameraUseCase {
  final AgoraRepository repository;
  const ToggleCameraUseCase(this.repository);

  Future<Either<Failure, void>> call(bool enabled) {
    return repository.toggleCamera(enabled);
  }
}
