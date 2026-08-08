import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/profile_repository.dart';

class GetMutualGroupsCountUseCase {
  final ProfileRepository repository;
  const GetMutualGroupsCountUseCase(this.repository);

  Future<Either<Failure, int>> call({required String uid, required String otherUid}) {
    return repository.getMutualGroupsCount(uid: uid, otherUid: otherUid);
  }
}
