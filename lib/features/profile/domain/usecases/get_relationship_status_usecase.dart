import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/profile_visibility.dart';
import '../repositories/profile_repository.dart';

class GetRelationshipStatusUseCase {
  final ProfileRepository repository;
  const GetRelationshipStatusUseCase(this.repository);

  Future<Either<Failure, ProfileVisibility>> call({
    required String viewerUid,
    required String profileUid,
  }) {
    if (viewerUid == profileUid) {
      return Future.value(const Right(ProfileVisibility.owner));
    }
    return repository.getRelationshipStatus(viewerUid: viewerUid, profileUid: profileUid);
  }
}
