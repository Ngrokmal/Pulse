import '../repositories/admin_repository.dart';

class WatchAdminActivityUseCase {
  final AdminRepository repository;
  const WatchAdminActivityUseCase(this.repository);

  Stream<void> call() => repository.watchAdminActivity();
}
