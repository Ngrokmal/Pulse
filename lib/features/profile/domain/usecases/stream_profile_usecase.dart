import '../entities/profile_entity.dart';
import '../repositories/profile_repository.dart';

class StreamProfileUseCase {
  final ProfileRepository repository;
  const StreamProfileUseCase(this.repository);

  Stream<ProfileEntity> call(String uid) => repository.streamProfile(uid);
}
