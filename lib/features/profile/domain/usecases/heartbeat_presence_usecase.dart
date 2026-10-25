import '../repositories/profile_repository.dart';

class HeartbeatPresenceUseCase {
  final ProfileRepository repository;
  const HeartbeatPresenceUseCase(this.repository);

  Future<void> call({required String uid, required String deviceId}) {
    return repository.heartbeatPresence(uid: uid, deviceId: deviceId);
  }
}
