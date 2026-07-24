import '../repositories/profile_repository.dart';

class SetOnlineStatusUseCase {
  final ProfileRepository repository;
  const SetOnlineStatusUseCase(this.repository);

  Future<void> call({required String uid, required bool isOnline}) {
    return repository.setOnlineStatus(uid: uid, isOnline: isOnline);
  }
}
