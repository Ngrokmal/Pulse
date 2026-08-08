import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/agora_repository.dart';

/// Front/back camera switch (Phase 1 §6).
class SwitchCameraUseCase {
  final AgoraRepository repository;
  const SwitchCameraUseCase(this.repository);

  Future<Either<Failure, void>> call() {
    return repository.switchCamera();
  }
}
