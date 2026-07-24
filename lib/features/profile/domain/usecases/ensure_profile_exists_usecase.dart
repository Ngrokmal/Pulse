import '../repositories/profile_repository.dart';

class EnsureProfileExistsUseCase {
  final ProfileRepository repository;
  const EnsureProfileExistsUseCase(this.repository);

  Future<void> call({
    required String uid,
    required String username,
    required String displayName,
    String? email,
  }) {
    return repository.ensureProfileExists(
      uid: uid,
      username: username,
      displayName: displayName,
      email: email,
    );
  }
}
